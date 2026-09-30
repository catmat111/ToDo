module DashboardHelper
  # "2 de 5 subtarefas"
  def subtask_summary(task)
    done, total = task.progress
    return if total.zero?
    "#{done} de #{total} #{total == 1 ? 'subtarefa' : 'subtarefas'}"
  end

  def dashboard_due_label(task)
    return relative_due(task.due_at) unless task.overdue?
    "Atrasada · #{relative_due(task.due_at)}"
  end
end
