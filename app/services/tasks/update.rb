module Tasks
  # Saves the edit form of a task.
  #
  #   Tasks::Update.call(task, params: { title: "Novo", status: "completed", tag_ids: [ "" ] })
  #
  # - tag_ids are filtered to the owner's tags (a blank list removes every tag);
  # - a status change goes through Tasks::ChangeStatus / Tasks::Complete so transitions,
  #   audit and recurrence behave exactly like the quick action buttons;
  # - everything happens in one transaction.
  class Update
    PERMITTED = %i[title description task_type status priority starts_at due_at parent_task_id
                   job_application_id sync_to_calendar tag_ids].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(task, params:)
      @task = task
      @params = params.to_h.symbolize_keys.slice(*PERMITTED)
    end

    def call
      new_status = params.delete(:status).presence
      tag_ids = params.key?(:tag_ids) ? OwnedTagIds.call(task.user, params.delete(:tag_ids)) : nil
      status_change = new_status && new_status != task.status
      next_task = nil

      task.assign_attributes(params)
      valid = task.valid? # runs first: valid? resets the errors collection
      return failure unless status_allowed?(new_status) && valid

      ActiveRecord::Base.transaction do
        changed = task.changed
        task.save!
        if tag_ids && tag_ids.sort != task.tag_ids.sort
          task.tag_ids = tag_ids
          changed << "tags"
        end
        if status_change
          result = new_status == "completed" ? Complete.call(task) : ChangeStatus.call(task, to: new_status)
          unless result.success?
            task.errors.add(:status, result.error)
            raise ActiveRecord::Rollback
          end
          next_task = result.next_task
        end
        AuditLog.record("task.updated", resource: task, user: task.user, fields: changed) if changed.any?
      end

      task.errors.any? ? failure : Result.new(success: true, task: task, next_task: next_task)
    end

    private
      attr_reader :task, :params

      def status_allowed?(new_status)
        return true if new_status.nil? || new_status == task.status
        return true if task.can_transition_to?(new_status)
        task.errors.add(:status, "não pode passar de «#{task.status_label}» para «#{Task.status_label(new_status)}»")
        false
      end

      def failure
        Result.new(success: false, task: task, error: task.errors.full_messages.to_sentence)
      end
  end
end
