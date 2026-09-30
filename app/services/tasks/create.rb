module Tasks
  # Creates a task (or subtask) for a user — plan flow A.
  #
  #   Tasks::Create.call(user: Current.user, params: { title: "Estudar", tag_ids: [ "1" ], reminder_at: "2026-10-01T09:00" })
  #
  # - tag_ids are filtered to the user's own tags;
  # - parent_task / job_application ownership is enforced by Task validations;
  # - reminder_at (virtual) becomes the task's first in-app reminder, in the same transaction;
  # - new subtasks go to the end of their parent's list.
  class Create
    PERMITTED = %i[title description task_type priority starts_at due_at parent_task_id
                   job_application_id sync_to_calendar reminder_at tag_ids].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params.to_h.symbolize_keys.slice(*PERMITTED)
    end

    def call
      tag_ids = params.key?(:tag_ids) ? OwnedTagIds.call(user, params.delete(:tag_ids)) : []
      task = user.tasks.new(params)
      task.tag_ids = tag_ids if tag_ids.any?
      task.position = next_position(task.parent_task) if task.parent_task

      ActiveRecord::Base.transaction do
        task.save!
        task.reminders.create!(remind_at: task.reminder_at) if task.reminder_at.present?
      end

      AuditLog.record("task.created", resource: task, user: user,
                      parent_task_id: task.parent_task_id, task_type: task.task_type,
                      reminder: task.reminder_at.present?)
      Result.new(success: true, task: task)
    rescue ActiveRecord::RecordInvalid => e
      task.errors.merge!(e.record.errors) unless e.record == task
      Result.new(success: false, task: task, error: task.errors.full_messages.to_sentence)
    end

    private
      attr_reader :user, :params

      def next_position(parent)
        return 0 unless parent.persisted? && parent.user_id == user.id
        parent.subtasks.maximum(:position).to_i + 1
      end
  end
end
