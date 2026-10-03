module Calendar
  # Full synchronisation of one Google connection:
  #
  #   1. skips unless the connection is active;
  #   2. refreshes the access token when needed;
  #   3. syncs every eligible task (Task.calendar_eligible) via TaskSync;
  #   4. removes external events whose task is gone or no longer eligible;
  #   5. stamps connection.last_synced_at.
  #
  # Per-task API errors are recorded on the CalendarEvent and do not abort the
  # run. Network failures abort it (the job retries later: the sync is
  # idempotent). Authentication failures mark the connection as error and raise
  # Calendar::AuthorizationError, which jobs discard: no retry loop.
  class Sync
    Result = Struct.new(:created, :updated, :unchanged, :imported, :conflicts, :removed, :failed, keyword_init: true) do
      def self.empty
        new(created: 0, updated: 0, unchanged: 0, imported: 0, conflicts: 0, removed: 0, failed: 0)
      end

      def synced
        created + updated + unchanged + imported
      end
    end

    OUTCOME_COUNTERS = {
      created: :created, updated: :updated, unchanged: :unchanged, imported: :imported,
      conflict: :conflicts, removed: :removed
    }.freeze

    attr_reader :connection, :client, :result

    def initialize(connection, client: Calendar.client, resolve_conflicts: false)
      @connection = connection
      @client = client
      @resolve_conflicts = resolve_conflicts
      @result = Result.empty
    end

    def call
      return nil unless connection.active?

      with_authorization do
        @result = Result.empty # a retry after a forced refresh starts the count again
        sync_eligible_tasks
        remove_stale_events
      end
      connection.update!(last_synced_at: Time.current, last_error: summary_error)
      result
    end

    # Syncs (or removes) a single task's event. Used by CalendarTaskSyncJob.
    def sync_task(task)
      return nil unless connection.active?

      with_authorization { task_sync(task).call }
    end

    # Deletes one external event (task destroyed). A missing event is fine.
    def delete_event(external_event_id)
      return nil unless connection.active?

      with_authorization { delete_remote(external_event_id) }
      connection.calendar_events.where(external_event_id: external_event_id).destroy_all
      true
    end

    private
      def access_token
        @access_token ||= TokenRefresher.call(connection, client: client)
      end

      # A 401 with a token we believed valid gets exactly one forced refresh;
      # a second rejection is final.
      def with_authorization
        yield
      rescue GoogleClient::AuthError
        if @forced_refresh
          AuthFailure.call(connection)
          raise AuthorizationError, AuthFailure::MESSAGE
        end
        @forced_refresh = true
        @access_token = TokenRefresher.call(connection, client: client, force: true)
        retry
      end

      def task_sync(task)
        TaskSync.new(connection, task, client: client, access_token: access_token, resolve_conflicts: @resolve_conflicts)
      end

      def eligible_tasks
        connection.user.tasks.calendar_eligible
      end

      def sync_eligible_tasks
        eligible_tasks.find_each do |task|
          count task_sync(task).call
        rescue GoogleClient::AuthError, GoogleClient::NetworkError
          raise
        rescue GoogleClient::Error, ActiveRecord::ActiveRecordError, ArgumentError => e
          result.failed += 1
          Rails.logger.warn("[calendar] task #{task.id} failed to sync: #{e.class}")
        end
      end

      def remove_stale_events
        events = connection.calendar_events
        stale = events.where(task_id: nil).or(events.where.not(task_id: eligible_tasks.select(:id)))
        stale.find_each do |calendar_event|
          delete_remote(calendar_event.external_event_id)
          calendar_event.destroy!
          count :removed
        rescue GoogleClient::AuthError, GoogleClient::NetworkError
          raise
        rescue GoogleClient::Error, ActiveRecord::ActiveRecordError => e
          result.failed += 1
          Rails.logger.warn("[calendar] event #{calendar_event.id} could not be removed: #{e.class}")
        end
      end

      def delete_remote(external_event_id)
        return if external_event_id.blank?

        client.delete_event(calendar_id: connection.calendar_id.presence || "primary",
                            access_token: access_token, event_id: external_event_id)
      rescue GoogleClient::NotFoundError
        nil
      end

      def count(outcome)
        counter = OUTCOME_COUNTERS[outcome]
        result[counter] += 1 if counter
      end

      def summary_error
        problems = result.failed + result.conflicts
        return nil if problems.zero?

        "#{problems} #{problems == 1 ? "tarefa não sincronizou" : "tarefas não sincronizaram"} — consulta os detalhes abaixo."
      end
  end
end
