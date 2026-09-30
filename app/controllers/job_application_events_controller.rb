class JobApplicationEventsController < ApplicationController
  before_action :set_job_application

  def create
    @event = @job_application.job_application_events.new(event_params)

    if @event.save
      AuditLog.record("job_application.event_added", resource: @job_application,
                      event_id: @event.id, event_type: @event.event_type)
      redirect_to job_application_path(@job_application, anchor: "historico"),
                  notice: "Evento adicionado ao histórico.", status: :see_other
    else
      render "job_applications/show", status: :unprocessable_entity
    end
  end

  def destroy
    event = @job_application.job_application_events.find(params[:id])
    event.destroy!
    AuditLog.record("job_application.event_deleted", resource: @job_application,
                    event_id: event.id, event_type: event.event_type)
    redirect_to job_application_path(@job_application, anchor: "historico"),
                notice: "Evento removido do histórico.", status: :see_other
  end

  private
    def set_job_application
      @job_application = Current.user.job_applications.find(params[:job_application_id])
    end

    def event_params
      params.expect(job_application_event: [ :event_type, :occurred_at, :notes ])
    end
end
