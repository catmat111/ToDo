class RemindersController < ApplicationController
  before_action :set_task

  def create
    @reminder = @task.reminders.build(reminder_params)

    if @reminder.save
      AuditLog.record("reminder.created", resource: @reminder, task_id: @task.id, channel: @reminder.channel)
      redirect_back_or_to task_path(@task), notice: "Lembrete criado para #{helpers.format_datetime(@reminder.remind_at)}."
    else
      redirect_back_or_to task_path(@task), alert: failure_message(@reminder)
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_back_or_to task_path(@task), alert: "Já existe um lembrete para esse momento neste canal."
  end

  def destroy
    reminder = @task.reminders.find(params[:id])
    reminder.destroy!
    AuditLog.record("reminder.destroyed", resource: reminder, task_id: @task.id)
    redirect_back_or_to task_path(@task), notice: "Lembrete removido.", status: :see_other
  end

  private
    def set_task
      @task = Current.user.tasks.find(params[:task_id])
    end

    def reminder_params
      params.expect(reminder: [ :remind_at, :channel ])
    end

    def failure_message(reminder)
      messages = reminder.errors.full_messages
      "Não foi possível criar o lembrete: #{messages.to_sentence.downcase_first}."
    end
end
