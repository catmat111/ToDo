require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @task = create_task(@user, title: "Preparar apresentação", description: "Slides e ensaio")
  end

  # ---------- index ----------

  test "requires authentication" do
    sign_out
    get tasks_url
    assert_redirected_to new_session_url
  end

  test "index lists the user's root-level active tasks" do
    child = create_task(@user, title: "Passo escondido", parent_task: @task)
    create_task(@user, title: "Arquivada antiga", archived_at: Time.current)
    create_task(users(:two), title: "Tarefa do Bruno")

    get tasks_url
    assert_response :success
    assert_select "h1", "Tarefas"
    assert_select "#task_#{@task.id} .list__title", "Preparar apresentação"
    assert_select "#task_#{child.id}", count: 0
    assert_select ".list__title", text: "Arquivada antiga", count: 0
    assert_select ".list__title", text: "Tarefa do Bruno", count: 0
    assert_select "#task_#{@task.id} .task-progress"
  end

  test "index search, filters and toggles" do
    create_task(@user, title: "Estudar física", task_type: "exam", priority: 3, due_at: 1.day.ago)
    child = create_task(@user, title: "Rever slides", parent_task: @task)

    get tasks_url(q: "FÍSICA".downcase)
    assert_select ".list__title", count: 1, text: "Estudar física"

    get tasks_url(q: "slides")
    assert_select ".list__title", text: "Rever slides"
    assert_select ".list__title", text: "Preparar apresentação"

    get tasks_url(task_type: "exam")
    assert_select ".list__title", count: 1

    get tasks_url(due: "overdue")
    assert_select ".badge--overdue"
    assert_select ".list__title", count: 1, text: "Estudar física"

    get tasks_url(subtasks: "1")
    assert_select "#task_#{child.id}"

    get tasks_url(status: "completed")
    assert_select ".empty-state"
  end

  test "index filters by tag and shows the archived tab" do
    tag = @user.tags.create!(name: "Faculdade", color: "#6E6B41")
    tagged = create_task(@user, title: "Com etiqueta", tags: [ tag ])
    archived = create_task(@user, title: "Guardada", archived_at: Time.current)

    get tasks_url(tag_id: tag.id)
    assert_select ".list__title", count: 1, text: tagged.title
    assert_select "#task_#{tagged.id} .chip", "Faculdade"

    get tasks_url(archived: "1")
    assert_select ".list__title", count: 1, text: archived.title
    assert_select ".tabs__link.is-active", /Arquivadas/
  end

  test "index paginates" do
    now = Time.current
    Task.insert_all!(Array.new(55) { |i| { user_id: @user.id, title: "Lote #{i}", created_at: now, updated_at: now } })

    get tasks_url
    assert_select ".task-list > li", 50
    assert_select "a[rel=next][href*='page=2']"

    get tasks_url(page: 2)
    assert_select ".task-list > li", 6
    assert_select "a[rel=prev]"
  end

  test "index shows an empty state for a new user" do
    sign_in_as users(:two)
    get tasks_url
    assert_select ".empty-state__title", "Ainda não tens tarefas"
  end

  # ---------- show ----------

  test "show renders details, breadcrumb, subtasks and valid actions only" do
    child = create_task(@user, title: "Fazer slides", parent_task: @task)
    grandchild = create_task(@user, title: "Escolher imagens", parent_task: child)

    get task_url(grandchild)
    assert_response :success
    assert_select ".breadcrumb a", text: "Preparar apresentação"
    assert_select ".breadcrumb a", text: "Fazer slides"

    get task_url(@task)
    assert_select "h1", "Preparar apresentação"
    assert_select ".task-description", /Slides e ensaio/
    assert_select "#task_#{child.id}"
    assert_select "form.task-quick-add input[name='task[parent_task_id]'][value='#{@task.id}']"
    assert_select "form[action='#{start_task_path(@task)}']"
    assert_select "form[action='#{complete_task_path(@task)}']"
    assert_select "form[action='#{reopen_task_path(@task)}']", count: 0
    assert_select "form[action='#{task_recurrence_path(@task)}']"
    assert_select ".task-suggestion", count: 0
  end

  test "show suggests completing the parent when every subtask is done" do
    child = create_task(@user, parent_task: @task)
    child.update!(status: "completed")

    get task_url(@task)
    assert_select ".task-suggestion", /Todas as subtarefas estão concluídas — concluir esta tarefa\?/
    assert @task.reload.pending?, "never auto-completes"
  end

  test "show links the job application" do
    application = create_job_application(@user, title: "Dev Rails")
    @task.update!(job_application: application)

    get task_url(@task)
    assert_select "a[href='#{job_application_path(application)}']", /Dev Rails/
  end

  # ---------- new / create ----------

  test "new renders the form with the user's options" do
    tag = @user.tags.create!(name: "Pessoal")
    users(:two).tags.create!(name: "Segredo")
    get new_task_url
    assert_response :success
    assert_select "input[name='task[title]']"
    assert_select "select[name='task[status]']", count: 0
    assert_select "input[type=datetime-local][name='task[reminder_at]']"
    assert_select "input[type=hidden][name='task[tag_ids][]'][value='']"
    assert_select "input[type=checkbox][name='task[tag_ids][]'][value='#{tag.id}']"
    assert_select "label", text: "Segredo", count: 0
  end

  test "new prefills the parent from the query string, only for own tasks" do
    get new_task_url(parent_task_id: @task.id)
    assert_select "select[name='task[parent_task_id]'] option[selected][value='#{@task.id}']"
    assert_select "h1", "Nova subtarefa"

    foreign = create_task(users(:two), title: "Do Bruno")
    get new_task_url(parent_task_id: foreign.id)
    assert_select "h1", "Nova tarefa"
    assert_no_match "Do Bruno", response.body
  end

  test "create saves the task with tags and a reminder" do
    tag = @user.tags.create!(name: "Trabalho")
    foreign_tag = users(:two).tags.create!(name: "Alheia")
    remind_at = 2.days.from_now.change(sec: 0)

    assert_difference -> { @user.tasks.count } => 1, -> { Reminder.count } => 1 do
      post tasks_url, params: { task: {
        title: "Entregar relatório", task_type: "delivery", priority: "2",
        due_at: 3.days.from_now.strftime("%Y-%m-%dT%H:%M"), reminder_at: remind_at.strftime("%Y-%m-%dT%H:%M"),
        tag_ids: [ "", tag.id, foreign_tag.id ], sync_to_calendar: "1"
      } }
    end

    task = @user.tasks.order(:id).last
    assert_redirected_to task_url(task)
    assert_equal "Tarefa criada.", flash[:notice]
    assert task.type_delivery?
    assert task.sync_to_calendar?
    assert_equal [ tag ], task.tags.to_a, "tag_ids from another user are ignored"
    assert_equal remind_at, task.reminders.first.remind_at
  end

  test "create a subtask from the quick-add form redirects to the parent" do
    assert_difference -> { @task.subtasks.count } => 1 do
      post tasks_url, params: { task: { title: "Ensaiar", parent_task_id: @task.id } }
    end
    assert_redirected_to task_url(@task)
  end

  test "create rejects a parent_task_id of another user" do
    foreign = create_task(users(:two), title: "Projeto do Bruno")
    assert_no_difference -> { Task.count } do
      post tasks_url, params: { task: { title: "Intrusa", parent_task_id: foreign.id } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_no_match "Projeto do Bruno", response.body
  end

  test "create with invalid data re-renders the form" do
    assert_no_difference -> { Task.count } do
      post tasks_url, params: { task: { title: "", starts_at: "2026-10-10T10:00", due_at: "2026-10-09T10:00" } }
    end
    assert_response :unprocessable_entity
    assert_select ".field__error", /não pode ficar em branco/
    assert_select ".field__error", /não pode ser anterior ao início/
  end

  test "create ignores status and assigns the task to the current user" do
    post tasks_url, params: { task: { title: "Nova", status: "completed" } }
    task = Task.order(:id).last
    assert task.pending?
    assert_equal @user, task.user
  end

  # ---------- edit / update ----------

  test "edit offers only valid statuses and parents outside the subtree" do
    child = create_task(@user, parent_task: @task)
    other = create_task(@user, title: "Outra")

    get edit_task_url(@task)
    assert_response :success
    assert_select "select[name='task[status]'] option", 4
    assert_select "select[name='task[parent_task_id]'] option[value='#{@task.id}']", count: 0
    assert_select "select[name='task[parent_task_id]'] option[value='#{child.id}']", count: 0
    assert_select "select[name='task[parent_task_id]'] option[value='#{other.id}']"

    @task.update!(status: "completed")
    get edit_task_url(@task)
    assert_select "select[name='task[status]'] option", 2
  end

  test "update changes the task and its tags" do
    tag = @user.tags.create!(name: "Velha")
    @task.tags << tag

    patch task_url(@task), params: { task: { title: "Apresentação final", priority: "3", tag_ids: [ "" ] } }

    assert_redirected_to task_url(@task)
    @task.reload
    assert_equal "Apresentação final", @task.title
    assert_equal 3, @task.priority
    assert_empty @task.tags
  end

  test "update to completed through the form sets completed_at" do
    patch task_url(@task), params: { task: { status: "completed" } }
    assert_redirected_to task_url(@task)
    assert_not_nil @task.reload.completed_at
  end

  test "update rejects an invalid status transition" do
    @task.update!(status: "completed")
    patch task_url(@task), params: { task: { status: "cancelled" } }
    assert_response :unprocessable_entity
    assert @task.reload.completed?
  end

  test "update rejects a cycle and a foreign parent" do
    child = create_task(@user, parent_task: @task)
    patch task_url(@task), params: { task: { parent_task_id: child.id } }
    assert_response :unprocessable_entity
    assert_nil @task.reload.parent_task_id

    patch task_url(@task), params: { task: { parent_task_id: create_task(users(:two)).id } }
    assert_response :unprocessable_entity
    assert_nil @task.reload.parent_task_id
  end

  # ---------- member actions ----------

  test "complete_all completes every open task matching the filters" do
    other = create_task(@user, title: "Segunda")
    done = create_task(@user, title: "Já feita")
    done.update!(status: "completed")
    other_user_task = create_task(users(:two), title: "De outra pessoa")

    patch complete_all_tasks_url
    assert_redirected_to tasks_url
    assert @task.reload.completed?
    assert other.reload.completed?
    assert other_user_task.reload.pending?

    get tasks_url
    assert_response :success
  end

  test "destroy_all deletes only the selected tasks" do
    keep = create_task(@user, title: "Manter")
    other = create_task(users(:two), title: "Alheia")

    assert_difference -> { Task.count }, -1 do
      delete destroy_all_tasks_url, params: { ids: [ @task.id, other.id ] }
    end
    assert_redirected_to tasks_url
    assert_not Task.exists?(@task.id)
    assert Task.exists?(keep.id)
    assert Task.exists?(other.id)
  end

  test "destroy_all with all=1 deletes every task matching the filters" do
    create_task(@user, title: "Segunda")
    other = create_task(users(:two), title: "Alheia")

    delete destroy_all_tasks_url, params: { all: "1" }
    assert_equal 0, @user.tasks.count
    assert Task.exists?(other.id)
  end

  test "complete, reopen, start and cancel follow the transitions" do
    patch start_task_url(@task)
    assert @task.reload.in_progress?

    patch complete_task_url(@task), headers: { "HTTP_REFERER" => tasks_url }
    assert_redirected_to tasks_url
    assert @task.reload.completed?
    assert_not_nil @task.completed_at

    patch start_task_url(@task)
    assert_redirected_to task_url(@task)
    assert_match "Não é possível passar", flash[:alert]
    assert @task.reload.completed?

    patch reopen_task_url(@task)
    assert @task.reload.pending?
    assert_nil @task.completed_at

    patch cancel_task_url(@task)
    assert @task.reload.cancelled?
  end

  test "completing a parent keeps the subtasks open" do
    child = create_task(@user, parent_task: @task)
    patch complete_task_url(@task)
    assert @task.reload.completed?
    assert child.reload.pending?
  end

  test "completing a recurring task schedules the next occurrence" do
    @task.update!(due_at: Time.zone.local(2026, 10, 1, 9, 0))
    TaskRecurrence.create!(task: @task, frequency: "weekly", interval: 1)

    assert_difference -> { @user.tasks.count } => 1 do
      patch complete_task_url(@task)
    end
    assert_match "Próxima ocorrência agendada", flash[:notice]
    assert_equal Time.zone.local(2026, 10, 8, 9, 0), @user.tasks.order(:id).last.due_at
  end

  test "archive and unarchive" do
    patch archive_task_url(@task)
    assert @task.reload.archived?
    assert AuditLog.exists?(action: "task.archived", resource_id: @task.id)

    patch unarchive_task_url(@task)
    assert_not @task.reload.archived?
  end

  test "destroy deletes the task and audits it with the title" do
    assert_difference -> { Task.count } => -1 do
      delete task_url(@task)
    end
    assert_redirected_to tasks_url
    log = AuditLog.where(action: "task.deleted").last
    assert_equal "Preparar apresentação", log.metadata["title"]
  end

  test "destroying a subtask goes back to the parent" do
    child = create_task(@user, parent_task: @task)
    delete task_url(child)
    assert_redirected_to task_url(@task)
  end

  # ---------- authorization ----------

  test "another user gets 404 on every member route" do
    sign_in_as users(:two)

    get task_url(@task)
    assert_response :not_found
    get edit_task_url(@task)
    assert_response :not_found
    patch task_url(@task), params: { task: { title: "Hackeada" } }
    assert_response :not_found
    %i[complete reopen start cancel archive unarchive].each do |action|
      patch url_for([ action, @task ])
      assert_response :not_found
    end
    assert_no_difference -> { Task.count } do
      delete task_url(@task)
    end
    assert_response :not_found

    @task.reload
    assert_equal "Preparar apresentação", @task.title
    assert @task.pending?
    assert_not @task.archived?
  end
end
