class TasksController < ApplicationController
  before_action :set_task, except: %i[index new create]
  before_action :set_form_options, only: %i[new create edit update]

  def index
    @filter = Tasks::Filter.new(Current.user, params)
    @tasks = @filter.tasks
    @tags = Current.user.tags.alphabetical
    @open_count = Current.user.tasks.active.open.count
    @overdue_count = Current.user.tasks.active.overdue.count
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

    if result.success?
      if @task.parent_task
        redirect_to @task.parent_task, notice: "Subtarefa «#{@task.title}» criada."
      else
        redirect_to @task, notice: "Tarefa criada."
      end
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

  def reopen
    respond_with_result(Tasks::ChangeStatus.call(@task, to: "pending"), "Tarefa reaberta.")
  end

  def start
    respond_with_result(Tasks::ChangeStatus.call(@task, to: "in_progress"), "Tarefa em curso.")
  end

  def cancel
    respond_with_result(Tasks::ChangeStatus.call(@task, to: "cancelled"), "Tarefa cancelada.")
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

    def with_next_occurrence(message, next_task)
      return message unless next_task
      due = next_task.due_at || next_task.starts_at
      suffix = due ? " para #{I18n.l(due, format: '%d/%m/%Y %H:%M')}" : ""
      "#{message} Próxima ocorrência agendada#{suffix}."
    end
end
