class TasksController < ApplicationController
  before_action :set_task, except: %i[index new create complete_all destroy_all]
  before_action :set_form_options, only: %i[new create edit update]

  def index
    @filter = Tasks::Filter.new(Current.user, params)
    @tasks = @filter.tasks
    @tags = Current.user.tags.alphabetical
    @open_count = Current.user.tasks.active.open.count
    @overdue_count = Current.user.tasks.active.overdue.count
    @completable_count = @filter.archived? ? 0 : @filter.scope.open.count
    @matching_count = @filter.scope.count
  end

  def show
    @subtasks = @task.preload_subtasks
  end

  def new
    @task = Current.user.tasks.new(parent_task: requested_parent)
    @task.task_type = @task.parent_task.task_type if @task.parent_task
  end

  def create
    result = Tasks::Create.call(user: Current.user, params: task_params.except(:status))
    @task = result.task

    # Quick-add chat (bottom-right button): answer with Turbo Streams, no page reload.
    if params[:return_to] == "chat"
      return respond_to do |format|
        format.turbo_stream do
          streams = [ turbo_stream.append("quickadd_messages", partial: "tasks/quickadd_reply",
                                                               locals: { task: @task, ok: result.success? }) ]
          streams << turbo_stream.append("home-today-list", partial: "dashboard/task", locals: { task: @task }) if result.success?
          render turbo_stream: streams
        end
        format.html { redirect_back_or_to root_path, (result.success? ? :notice : :alert) => (result.success? ? "Tarefa adicionada." : @task.errors.full_messages.to_sentence) }
      end
    end

    if result.success?
      if params[:return_to] == "home"
        redirect_to root_path, notice: home_notice(@task)
      elsif @task.parent_task
        redirect_to @task.parent_task, notice: "Subtarefa «#{@task.title}» criada."
      else
        redirect_to @task, notice: "Tarefa criada."
      end
    elsif params[:return_to] == "home"
      redirect_to root_path, alert: result.task.errors.full_messages.to_sentence
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    result = Tasks::Update.call(@task, params: task_params.except(:reminder_at))

    if result.success?
      redirect_to @task, notice: with_next_occurrence("Tarefa atualizada.", result.next_task)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    parent = @task.parent_task
    @task.destroy!
    AuditLog.record("task.deleted", resource: @task, title: @task.title, parent_task_id: parent&.id)
    redirect_to parent || tasks_path, notice: "Tarefa «#{@task.title}» eliminada.", status: :see_other
  end

  def complete
    result = Tasks::Complete.call(@task)
    respond_with_result(result, with_next_occurrence("Tarefa concluída.", result.next_task))
  end

  # Completes every open task matching the list filters (all pages, not just the visible one).
  def complete_all
    filter = Tasks::Filter.new(Current.user, params)
    done = 0
    filter.scope.open.to_a.each { |task| done += 1 if Tasks::Complete.call(task).success? }
    redirect_to tasks_path(filter.to_params),
                notice: (done == 1 ? "1 tarefa concluída." : "#{done} tarefas concluídas."), status: :see_other
  end

  # Deletes the selected tasks (ids[]) or, with all=1, every task matching the list filters.
  def destroy_all
    filter = Tasks::Filter.new(Current.user, params)
    ids = params[:all].present? ? filter.scope.pluck(:id) : Array(params[:ids]).map(&:to_i)
    deleted = 0
    ids.each do |id|
      task = Current.user.tasks.find_by(id: id) # subtasks may already be gone with their parent
      next unless task
      task.destroy!
      AuditLog.record("task.deleted", resource: task, title: task.title, parent_task_id: task.parent_task_id)
      deleted += 1
    end
    redirect_to tasks_path(filter.to_params),
                notice: (deleted == 1 ? "1 tarefa eliminada." : "#{deleted} tarefas eliminadas."), status: :see_other
  end

  def reopen
    respond_with_result(Tasks::ChangeStatus.call(@task, to: "pending"), "Tarefa reaberta.")
  end

  def start
    respond_with_result(Tasks::ChangeStatus.call(@task, to: "in_progress"), "Tarefa em curso.")
  end

  def cancel
    respond_with_result(Tasks::ChangeStatus.call(@task, to: "cancelled"), "Tarefa cancelada.")
  end

  # Dragged on the home page: to today, or to a tag's backlog (no date). Answers with a
  # page refresh (morphed, so the scroll stays).
  def plan
    tag = Current.user.tags.find(params[:tag_id]) if params[:tag_id].present?
    result = Tasks::Plan.call(@task, to: params[:to], tag: tag)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = result.error unless result.success?
        render turbo_stream: (result.success? ? turbo_stream.refresh(request_id: nil) : turbo_stream.update("flash", partial: "shared/flash"))
      end
      format.html { redirect_to root_path, (result.success? ? :notice : :alert) => (result.success? ? "Tarefa movida." : result.error), status: :see_other }
    end
  end

  def duplicate
    result = Tasks::Duplicate.call(@task)
    if result.success?
      redirect_to result.task, notice: "Tarefa duplicada. Estás agora na cópia.", status: :see_other
    else
      redirect_to @task, alert: "Não foi possível duplicar: #{result.error}", status: :see_other
    end
  end

  def archive
    respond_with_result(Tasks::Archive.call(@task), "Tarefa arquivada.")
  end

  def unarchive
    respond_with_result(Tasks::Archive.call(@task, archived: false), "Tarefa restaurada.")
  end

  private
    def set_task
      @task = Current.user.tasks.find(params[:id])
    end

    def task_params
      params.expect(task: [ :title, :description, :task_type, :status, :priority, :starts_at, :due_at,
                            :parent_task_id, :job_application_id, :sync_to_calendar, :reminder_at, tag_ids: [] ])
    end

    def requested_parent
      Current.user.tasks.find_by(id: params[:parent_task_id]) if params[:parent_task_id].present?
    end

    # Choices offered by the form, always scoped to the signed-in user.
    def set_form_options
      excluded = @task ? [ @task.id, *@task.descendant_ids ] : []
      parents = Current.user.tasks.active.where.not(id: excluded)
      parents = parents.or(Current.user.tasks.where(id: @task.parent_task_id)) if @task&.parent_task_id
      @parent_options = parents.order(Arel.sql("LOWER(tasks.title)")).pluck(:title, :id)
      @tags = Current.user.tags.alphabetical
      @job_applications = Current.user.job_applications.order(updated_at: :desc)
    end

    def respond_with_result(result, notice)
      if result.success?
        redirect_back_or_to @task, notice: notice, status: :see_other
      else
        redirect_back_or_to @task, alert: result.error, status: :see_other
      end
    end

    # Added from the home page: to today's list, or to a tag's backlog (no date).
    def home_notice(task)
      if task.due_at then "«#{task.title}» adicionada a hoje."
      elsif task.tags.any? then "«#{task.title}» adicionada a #{task.tags.map { |t| "«#{t.name}»" }.to_sentence}."
      else "«#{task.title}» adicionada."
      end
    end

    def with_next_occurrence(message, next_task)
      return message unless next_task
      due = next_task.due_at || next_task.starts_at
      suffix = due ? " para #{I18n.l(due, format: '%d/%m/%Y %H:%M')}" : ""
      "#{message} Próxima ocorrência agendada#{suffix}."
    end
end
