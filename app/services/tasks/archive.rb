module Tasks
  # Archives (or restores) a task. Archiving hides a task without losing its history —
  # the recommended alternative to deleting it.
  #
  #   Tasks::Archive.call(task)                    # archive
  #   Tasks::Archive.call(task, archived: false)   # restore
  class Archive
    def self.call(...)
      new(...).call
    end

    def initialize(task, archived: true)
      @task = task
      @archived = archived
    end

    def call
      if archived == task.archived?
        message = archived ? "A tarefa já está arquivada." : "A tarefa não está arquivada."
        return Result.new(success: false, task: task, error: message)
      end

      task.archived_at = archived ? Time.current : nil
      return Result.new(success: false, task: task, error: task.errors.full_messages.to_sentence) unless task.save

      AuditLog.record(archived ? "task.archived" : "task.unarchived", resource: task, user: task.user)
      Result.new(success: true, task: task)
    end

    private
      attr_reader :task, :archived
  end
end
