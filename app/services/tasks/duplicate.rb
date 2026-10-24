module Tasks
  # Copies a task as a new, pending one — with its tags, links and subtasks (the whole
  # tree, also pending). Not copied: reminders and the recurrence rule (the copy would
  # remind or repeat twice), completion and archive state.
  #
  #   copy = Tasks::Duplicate.call(task).task  # "Estudar (cópia)", next to the original
  class Duplicate
    def self.call(...)
      new(...).call
    end

    def initialize(task)
      @task = task
    end

    def call
      copy = nil
      ActiveRecord::Base.transaction do
        copy = copy_of(@task, parent_id: @task.parent_task_id, title: "#{@task.title} (cópia)".truncate(200))
        copy.update!(position: @task.position.to_i + 1) if @task.parent_task_id
      end
      AuditLog.record("task.duplicated", resource: copy, user: @task.user, source_id: @task.id)
      Result.new(success: true, task: copy)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, task: @task, error: e.record.errors.full_messages.to_sentence)
    end

    private
      def copy_of(original, parent_id:, title: original.title)
        copy = original.user.tasks.create!(
          title: title, description: original.description, task_type: original.task_type, priority: original.priority,
          starts_at: original.starts_at, due_at: original.due_at, sync_to_calendar: original.sync_to_calendar,
          parent_task_id: parent_id, position: original.position, job_application_id: original.job_application_id,
          tag_ids: original.tag_ids
        )
        original.links.each { |link| original.user.links.create!(linkable: copy, url: link.url, label: link.label) }
        original.subtasks.each { |subtask| copy_of(subtask, parent_id: copy.id) }
        copy
      end
  end
end
