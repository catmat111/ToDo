class TaskRecurrencesController < ApplicationController
  before_action :set_task

  def create
    save_recurrence(@task.recurrence || TaskRecurrence.new(task: @task), "Recorrência definida.")
  end

  def update
    save_recurrence(@task.recurrence || TaskRecurrence.new(task: @task), "Recorrência atualizada.")
  end

  def destroy
    if (recurrence = @task.recurrence)
      recurrence.destroy!
      AuditLog.record("task.recurrence_removed", resource: @task, frequency: recurrence.frequency)
    end
    redirect_to @task, notice: "A tarefa deixou de se repetir.", status: :see_other
  end

  private
    def set_task
      @task = Current.user.tasks.find(params[:task_id])
    end

    def recurrence_params
      params.expect(task_recurrence: [ :frequency, :interval, :ends_at ])
    end

    def save_recurrence(recurrence, notice)
      recurrence.assign_attributes(recurrence_params)
      if recurrence.save
        AuditLog.record("task.recurrence_set", resource: @task, frequency: recurrence.frequency,
                        interval: recurrence.interval, ends_at: recurrence.ends_at&.iso8601)
        redirect_to @task, notice: notice
      else
        @recurrence = recurrence
        @task.association(:recurrence).reset # the card summary shows the saved rule
        @subtasks = @task.preload_subtasks
        render "tasks/show", status: :unprocessable_entity
      end
    end
end
