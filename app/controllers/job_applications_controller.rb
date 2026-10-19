class JobApplicationsController < ApplicationController
  PER_PAGE = 10
  # Shown apart, at the top: what needs attention now.
  HIGHLIGHTED = %w[interview offer].freeze
  COMPENSATION_FIELDS = %i[work_mode salary_min salary_max salary_period].freeze

  before_action :set_job_application, only: %i[show edit update destroy transition create_task]

  # One list of every application, 10 at a time (more load while scrolling), with
  # interviews and offers highlighted on top. A status tab narrows the list.
  def index
    @query = params[:q].to_s.strip
    @status = params[:status].presence_in(JobApplication::STATUSES)
    @work_mode = params[:work_mode].presence_in(Compensation::WORK_MODES.keys)
    @min_salary = params[:min_salary].to_i if params[:min_salary].to_i.positive?
    @sort = params[:sort] == "salary" ? "salary" : nil
    @page = [ params[:page].to_i, 1 ].max

    applications = Current.user.job_applications
    @status_counts = applications.group(:status).count

    scope = applications.includes(:job_listing).search(@query).recent
    scope = scope.with_work_mode(@work_mode) if @work_mode
    scope = scope.paying_at_least(@min_salary) if @min_salary

    # Without a status tab the highlighted ones sit on top and leave the list below.
    @highlights = @status || @page > 1 ? [] : scope.where(status: HIGHLIGHTED).to_a
    list = @status ? scope.where(status: @status) : scope.where.not(status: HIGHLIGHTED)

    rows = if @sort == "salary"
      # Compare jobs: best monthly salary first, unknown salaries last.
      list.to_a.sort_by { |a| -(a.monthly_salary || -1) }.drop((@page - 1) * PER_PAGE).first(PER_PAGE + 1)
    else
      list.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    end
    @next_page = rows.size > PER_PAGE
    @job_applications = rows.first(PER_PAGE)
    @next_tasks = next_open_tasks_for(@job_applications + @highlights)

    render partial: "job_applications/page", locals: page_locals if turbo_frame_request? && @page > 1
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
    result = JobApplications::Create.call(user: Current.user, params: create_params, status: "applied")

    if result.success?
      notice = result.created? ? "Candidatura registada como enviada." : "Já tinhas uma candidatura para esta vaga."
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
    result = if attrs[:to] == "revert"
      JobApplications::Revert.call(@job_application)
    else
      JobApplications::Transition.call(
        @job_application,
        to: attrs[:to],
        occurred_at: attrs[:occurred_at].presence || Time.current,
        notes: attrs[:notes],
        create_follow_up: attrs[:create_follow_up],
        interview_at: attrs[:interview_at]
      )
    end

    if params[:return_to] == "index" && request.format.turbo_stream?
      return render_list_transition(result)
    end

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
    def page_locals
      { job_applications: @job_applications, next_tasks: @next_tasks, page: @page, next_page: @next_page }
    end

    # The status menu on the list: move the application where it now belongs (the
    # highlights or the list), without leaving the page or losing the scroll.
    def render_list_transition(result)
      application = result.job_application
      if result.success?
        flash.now[:notice] = transition_notice(result)
        next_task = next_open_tasks_for([ application ])[application.id]
        streams = [ turbo_stream.remove(helpers.dom_id(application, :row)), turbo_stream.remove(helpers.dom_id(application, :highlight)) ]
        streams << if HIGHLIGHTED.include?(application.status)
          turbo_stream.prepend("ja-highlights", partial: "job_applications/highlight", locals: { job_application: application, next_task: next_task })
        else
          turbo_stream.prepend("ja-list", partial: "job_applications/row", locals: { job_application: application, next_task: next_task })
        end
      else
        flash.now[:alert] = result.error
        streams = []
      end
      render turbo_stream: streams + [ turbo_stream.update("flash", partial: "shared/flash") ]
    end

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
