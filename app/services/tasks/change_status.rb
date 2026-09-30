module Tasks
  # Moves a task along Task::TRANSITIONS and records it in the audit log (plan §16).
  #
  #   Tasks::ChangeStatus.call(task, to: "in_progress")
  #
  # completed_at is kept in sync by the model. Completing should normally go through
  # Tasks::Complete, which also handles recurrence.
  class ChangeStatus
    AUDIT_ACTIONS = {
      "in_progress" => "task.started",
      "completed" => "task.completed",
      "cancelled" => "task.cancelled",
      "pending" => "task.reopened"
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(task, to:)
      @task = task
      @to = to.to_s
    end

    def call
      from = task.status
      return failure(unknown_status) if Task::STATUSES.exclude?(to)
      return failure(already_there) if from == to
      return failure(forbidden(from)) unless task.can_transition_to?(to)

      task.status = to
      unless task.save
        error = task.errors.full_messages.to_sentence
        task.status = from
        return failure(error)
      end

      AuditLog.record(AUDIT_ACTIONS.fetch(to), resource: task, user: task.user, from: from, to: to)
      Result.new(success: true, task: task)
    end

    private
      attr_reader :task, :to

      def failure(message)
        Result.new(success: false, task: task, error: message)
      end

      def unknown_status
        "Estado desconhecido."
      end

      def already_there
        "A tarefa já está «#{Task.status_label(to)}»."
      end

      def forbidden(from)
        "Não é possível passar de «#{Task.status_label(from)}» para «#{Task.status_label(to)}»."
      end
  end
end
