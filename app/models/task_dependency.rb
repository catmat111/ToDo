# "task is blocked by blocker": task can only start/complete once blocker is done.
class TaskDependency < ApplicationRecord
  belongs_to :task
  belongs_to :blocker, class_name: "Task"

  validates :blocker_id, uniqueness: { scope: :task_id, message: "já é uma dependência desta tarefa" }
  validate :not_itself
  validate :same_owner
  validate :no_cycle

  private
    def not_itself
      errors.add(:blocker, "não pode ser a própria tarefa") if task_id.present? && task_id == blocker_id
    end

    def same_owner
      return if task.nil? || blocker.nil?
      errors.add(:blocker, "tem de ser uma tarefa tua") if task.user_id != blocker.user_id
    end

    # Adding "task waits for blocker" is a cycle if blocker already (indirectly) waits for task.
    def no_cycle
      return if task_id.nil? || blocker_id.nil? || task_id == blocker_id
      seen = Set.new
      queue = [ blocker_id ]
      while (current = queue.shift)
        next unless seen.add?(current)
        if current == task_id
          errors.add(:blocker, "criaria um ciclo (essa tarefa já está à espera desta)")
          return
        end
        queue.concat(TaskDependency.where(task_id: current).pluck(:blocker_id))
      end
    end
end
