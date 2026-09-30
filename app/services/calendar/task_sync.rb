module Calendar
  # Synchronises ONE task with its Google Calendar event. Idempotent: the
  # CalendarEvent row (unique per connection + task) remembers the external id,
  # so running it twice never creates two remote events.
  #
  # Decision table for an eligible task that already has an external event:
  #
  #   task changed since last sync?  remote etag changed?  action
  #   no                             no                    nothing (verified)
  #   no                             yes                   import start/end into the task
  #   yes                            no                    update the event (If-Match etag)
  #   yes                            yes, times differ     conflict: neither side is overwritten
  #
  # Tasks that stopped being eligible (sync turned off, archived, no dates)
  # have their external event removed.
  #
  # Returns one of :created, :updated, :unchanged, :imported, :conflict,
  # :removed, :skipped. Google errors are recorded on the CalendarEvent and then
  # re-raised so the caller decides whether to continue or retry.
  class TaskSync
    CONFLICT_MESSAGE = "Conflito: a tarefa e o evento no Google Calendar foram alterados desde a última " \
                       "sincronização. Nenhum dos lados foi alterado.".freeze

    attr_reader :connection, :task, :client, :access_token

    def initialize(connection, task, client:, access_token:, resolve_conflicts: false)
      @connection = connection
      @task = task
      @client = client
      @access_token = access_token
      @resolve_conflicts = resolve_conflicts
    end

    def call
      task.calendar_eligible? ? upsert : remove
    end

    private
      def event
        @event ||= connection.calendar_events.find_or_initialize_by(task_id: task.id)
      end

      def calendar_id
        connection.calendar_id.presence || "primary"
      end

      def payload
        @payload ||= EventMapper.call(task)
      end

      # --- upsert ----------------------------------------------------------

      def upsert
        if event.external_event_id.blank?
          insert!
        elsif needs_push?
          push_update!
        else
          pull_remote_changes!
        end
      rescue GoogleCalendarClient::AuthError
        raise
      rescue GoogleCalendarClient::Error => e
        record_error!(e.message)
        raise
      end

      # The remote copy is stale when the last push failed/never happened or the
      # task was edited afterwards.
      def needs_push?
        !event.sync_synced? || event.last_synced_at.nil? || task.updated_at > event.last_synced_at
      end

      def insert!
        remote = client.insert_event(calendar_id: calendar_id, access_token: access_token, body: payload)
        mark_synced!(remote)
        :created
      end

      def push_update!
        etag = @resolve_conflicts ? nil : event.etag
        remote = client.update_event(calendar_id: calendar_id, access_token: access_token,
                                     event_id: event.external_event_id, body: payload, etag: etag)
        mark_synced!(remote)
        :updated
      rescue GoogleCalendarClient::NotFoundError
        insert!
      rescue GoogleCalendarClient::ConflictError
        resolve_remote_change!
      end

      # 412: the event changed in Google too. When the times Google holds are
      # already the ones we want (e.g. only the colour changed) we simply
      # overwrite with the current etag; otherwise both sides changed.
      def resolve_remote_change!
        remote = fetch_remote
        return insert! if remote.nil?
        return conflict! unless remote_times(remote) == EventMapper.times_for(task)

        updated = client.update_event(calendar_id: calendar_id, access_token: access_token,
                                      event_id: event.external_event_id, body: payload, etag: remote["etag"])
        mark_synced!(updated)
        :updated
      end

      def pull_remote_changes!
        remote = fetch_remote
        return insert! if remote.nil?

        if remote["etag"].present? && remote["etag"] == event.etag
          mark_synced!(remote)
          return :unchanged
        end

        imported = import_times!(remote)
        mark_synced!(remote)
        imported ? :imported : :unchanged
      end

      # nil when the event is gone (404/410 or cancelled in Google).
      def fetch_remote
        remote = client.get_event(calendar_id: calendar_id, access_token: access_token, event_id: event.external_event_id)
        remote["status"] == "cancelled" ? nil : remote
      rescue GoogleCalendarClient::NotFoundError
        nil
      end

      # "Importar alterações permitidas": only start/end come back into the task.
      def import_times!(remote)
        start_at, end_at = remote_times(remote)
        return false if start_at.nil? || end_at.nil?

        attributes = imported_attributes(start_at, end_at).reject { |name, value| task.public_send(name) == value }
        return false if attributes.empty?

        CalendarSyncable.without_sync { task.update!(attributes) }
        AuditLog.record("calendar.imported", resource: task, user: connection.user, fields: attributes.keys.map(&:to_s))
        true
      rescue ActiveRecord::RecordInvalid => e
        raise GoogleCalendarClient::Error, "Não foi possível importar a alteração do Google: #{e.record.errors.full_messages.to_sentence}"
      end

      def imported_attributes(start_at, end_at)
        if task.starts_at.present? && task.due_at.present?
          { starts_at: start_at, due_at: end_at }
        elsif task.due_at.present?
          { due_at: end_at }
        else
          { starts_at: start_at }
        end
      end

      # Only timed events are understood; all-day events ("date") are left alone.
      def remote_times(remote)
        start_at = parse_time(remote.dig("start", "dateTime"))
        end_at = parse_time(remote.dig("end", "dateTime"))
        [ start_at, end_at ]
      end

      def parse_time(value)
        value.present? ? Time.zone.parse(value.to_s)&.change(usec: 0) : nil
      rescue ArgumentError
        nil
      end

      def conflict!
        already_flagged = event.sync_error? && event.last_error == CONFLICT_MESSAGE
        event.update!(sync_status: "error", last_error: CONFLICT_MESSAGE)
        return :conflict if already_flagged

        connection.user.notifications.create!(
          notification_type: "calendar",
          notifiable: task,
          title: "Conflito de sincronização: #{task.title.truncate(80)}",
          body: "A tarefa e o evento correspondente no Google Calendar foram alterados ao mesmo tempo. " \
                "Nenhuma das versões foi substituída — revê as datas e resolve o conflito na página do Google Calendar."
        )
        AuditLog.record("calendar.conflict", resource: task, user: connection.user)
        :conflict
      end

      def mark_synced!(remote)
        event.update!(
          external_event_id: remote["id"].presence || event.external_event_id,
          etag: remote["etag"],
          sync_status: "synced",
          last_error: nil,
          last_synced_at: Time.current
        )
      end

      def record_error!(message)
        event.sync_status = "error"
        event.last_error = message.to_s.truncate(500)
        event.save!
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.warn("[calendar] could not record sync error for task #{task.id}: #{e.class}")
      end

      # --- removal ---------------------------------------------------------

      def remove
        existing = connection.calendar_events.find_by(task_id: task.id)
        return :skipped if existing.nil?

        if existing.external_event_id.present?
          begin
            client.delete_event(calendar_id: calendar_id, access_token: access_token, event_id: existing.external_event_id)
          rescue GoogleCalendarClient::NotFoundError
            # Already gone in Google: nothing to do.
          end
        end
        existing.destroy!
        :removed
      end
  end
end
