class JobApplicationsController < ApplicationController
  VIEWS = %w[kanban list].freeze
  COMPENSATION_FIELDS = %i[work_mode salary_min salary_max salary_period].freeze

  before_action :set_job_application, only: %i[show edit update destroy transition create_task]

  def index
    @view = params[:view].presence_in(VIEWS) || "kanban"
    @query = params[:q].to_s.strip
    @status = params[:status].presence_in(JobApplication::STATUSES)

    applications = Current.user.job_applications
    @status_counts = applications.group(:status).count
    @applied_count = applications.where.not(applied_at: nil).count

    @work_mode = params[:work_mode].presence_in(Compensation::WORK_MODES.keys)
    @min_salary = params[:min_salary].to_i if params[:min_salary].to_i.positive?

    scope = applications.includes(:job_listing).search(@query).recent
    scope = scope.with_work_mode(@work_mode) if @work_mode
    scope = scope.paying_at_least(@min_salary) if @min_salary
    if @view == "list" && params[:sort] == "salary"
      # Compare jobs: best monthly salary first, unknown salaries last.
      list = @status ? scope.where(status: @status) : scope
      @job_applications = list.to_a.sort_by { |a| -(a.monthly_salary || -1) }
    elsif @view == "list"
      @job_applications = @status ? scope.where(status: @status) : scope
    else
      @job_applications = scope
      @columns = scope.group_by(&:status)
    end
    @next_tasks = next_open_tasks_for(@job_applications)
  end

  def show
    @event = new_event
  end

  def new
    @job_listing = Current.user.job_listings.find(params[:job_listing_id]) if params[:job_listing_id].present?
    if @job_listing && (existing = Current.user.job_applications.find_by(job_listing: @job_listing))
      redirect_to existing, notice: "Já tens uma candidatura para esta vaga."
      return
    end

    @job_application = Current.user.job_applications.new(
      job_listing: @job_listing, title: @job_listing&.title, company_name: @job_listing&.company_name
    )
  end

  def create
    result = JobApplications::Create.call(user: Current.user, params: create_params)

    if result.success?
      notice = result.created? ? "Candidatura criada." : "Já tinhas uma candidatura para esta vaga."
      redirect_to result.job_application, notice: notice, status: :see_other
    else
      @job_application = result.job_application
      @job_listing = @job_application.job_listing
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @job_application.update(update_params)
      changed = @job_application.saved_changes.keys - %w[updated_at]
      AuditLog.record("job_application.updated", resource: @job_application, fields: changed) if changed.any?
      redirect_to @job_application, notice: "Candidatura atualizada.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @job_application.destroy!
    AuditLog.record("job_application.deleted", resource: @job_application,
                    title: @job_application.title, status: @job_application.status)
    redirect_to job_applications_path, notice: "Candidatura apagada.", status: :see_other
  end

  def transition
    attrs = params.expect(transition: [ :to, :notes, :occurred_at, :create_follow_up, :interview_at ])
    result = JobApplications::Transition.call(
      @job_application,
      to: attrs[:to],
      occurred_at: attrs[:occurred_at].presence || Time.current,
      notes: attrs[:notes],
      create_follow_up: attrs[:create_follow_up],
      interview_at: attrs[:interview_at]
    )

    destination = params[:return_to] == "index" ? job_applications_path : @job_application
    if result.success?
      redirect_to destination, notice: transition_notice(result), status: :see_other
    else
      redirect_to destination, alert: result.error, status: :see_other
    end
  end

  def create_task
    result = JobApplications::CreateTask.call(@job_application)

    if result.success?
      redirect_to edit_task_path(result.tasks.first), status: :see_other,
                  notice: "Tarefa «#{result.tasks.first.title}» criada. Completa os detalhes."
    else
      redirect_to @job_application, alert: "Não foi possível criar a tarefa: #{result.error}", status: :see_other
    end
  end

  private
    def set_job_application
      @job_application = Current.user.job_applications.find(params[:id])
    end

    def create_params
      params.expect(job_application: [ :title, :company_name, :notes, :job_listing_id, :contact_id, *COMPENSATION_FIELDS ])
    end

    # Status only changes through #transition, never through a plain update.
    def update_params
      params.expect(job_application: [ :title, :company_name, :notes, :contact_id, *COMPENSATION_FIELDS ])
    end

    def new_event
      JobApplicationEvent.new(job_application_id: @job_application.id, event_type: "note",
                              occurred_at: Time.current.change(sec: 0))
    end

    # { job_application_id => earliest open, dated task } for the cards and table.
    def next_open_tasks_for(applications)
      ids = applications.map(&:id)
      return {} if ids.empty?

      Current.user.tasks.open.active.where(job_application_id: ids).where.not(due_at: nil)
             .order(due_at: :desc).index_by(&:job_application_id)
    end

    def transition_notice(result)
      message = "Candidatura movida para «#{result.job_application.status_label}»."
      titles = result.tasks.map { |task| "«#{task.title}»" }
      return message if titles.empty?

      "#{message} #{titles.one? ? 'Tarefa criada' : 'Tarefas criadas'}: #{titles.to_sentence}."
    end
end
