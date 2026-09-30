module Tasks
  # Completes a task — plan flow B.
  #
  #   result = Tasks::Complete.call(task)
  #   result.next_task # => next occurrence, when the task repeats
  #
  # - Subtasks are never touched: completing a parent doesn't complete its children.
  # - When the task has a recurrence, exactly ONE next occurrence is created (never a batch):
  #   title/description/type/priority/tags/calendar sync/parent are copied, starts_at/due_at are
  #   moved one step forward and the recurrence row moves to the new task. When the rule has
  #   ended (the next date would fall after ends_at) the rule is simply dropped.
  class Complete
    def self.call(...)
      new(...).call
    end

    def initialize(task)
      @task = task
    end

    def call
      next_task = nil
      result = nil

      ActiveRecord::Base.transaction do
        result = ChangeStatus.call(task, to: "completed")
        raise ActiveRecord::Rollback unless result.success?
        next_task = schedule_next_occurrence if task.recurrence
      end

      return result unless result.success?
      Result.new(success: true, task: task, next_task: next_task)
    rescue ActiveRecord::RecordInvalid => e
      task.reload
      Result.new(success: false, task: task,
                 error: "Não foi possível criar a próxima ocorrência: #{e.record.errors.full_messages.to_sentence}")
    end

    private
      attr_reader :task

      def schedule_next_occurrence
        recurrence = task.recurrence
        anchor = task.due_at || task.starts_at
        # Dateless routines repeat right away, but still honour ends_at.
        return end_rule(recurrence) if recurrence.next_time(anchor || Time.current).nil?

        next_task = build_next_occurrence(recurrence)
        next_task.save!
        recurrence.update!(task: next_task)
        task.association(:recurrence).reset

        AuditLog.record("task.recurred", resource: next_task, user: task.user,
                        previous_task_id: task.id, frequency: recurrence.frequency, interval: recurrence.interval)
        next_task
      end

      def build_next_occurrence(recurrence)
        task.user.tasks.new(
          title: task.title,
          description: task.description,
          task_type: task.task_type,
          priority: task.priority,
          sync_to_calendar: task.sync_to_calendar,
          parent_task_id: task.parent_task_id,
          position: task.position,
          starts_at: recurrence.advance(task.starts_at),
          due_at: recurrence.advance(task.due_at),
          tag_ids: task.tag_ids
        )
      end

      def end_rule(recurrence)
        recurrence.destroy!
        task.association(:recurrence).reset
        AuditLog.record("task.recurrence_ended", resource: task, user: task.user)
        nil
      end
  end
end
