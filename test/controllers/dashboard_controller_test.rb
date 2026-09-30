require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "requires authentication" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "renders empty states when the user has no data" do
    sign_in_as @user
    get root_path

    assert_response :success
    assert_select "h1", text: /(Bom dia|Boa tarde|Boa noite), Ana/
    assert_select ".dashboard-stats .stat", 4
    assert_select ".stat--terracotta .stat__label", "Para hoje"
    assert_select ".stat--mustard .stat__label", "Atrasadas"
    assert_select ".stat--olive .stat__label", "Em curso"
    assert_select ".stat--charcoal .stat__label", "Concluídas esta semana"
    assert_select ".empty-state__title", text: "Um dia em branco, à tua espera"
    assert_select "a[href=?]", new_task_path
    assert_select "a[href=?]", new_job_search_path
    %w[Hoje Atrasadas Próximos\ 7\ dias Em\ curso Candidaturas\ recentes Próximos\ lembretes Notificações\ por\ ler].each do |title|
      assert_select ".dashboard-panel .card__title", text: /#{title}/
    end
  end

  test "greets according to the hour in the user's time zone" do
    sign_in_as @user
    travel_to Time.utc(2030, 1, 15, 8, 0) do # 08:00 in Lisbon
      get root_path
      assert_select "h1", "Bom dia, Ana"
    end
    travel_to Time.utc(2030, 1, 15, 15, 0) do
      get root_path
      assert_select "h1", "Boa tarde, Ana"
    end
    travel_to Time.utc(2030, 1, 15, 22, 0) do
      get root_path
      assert_select "h1", "Boa noite, Ana"
    end
  end

  test "shows the objective as a quote" do
    @user.update!(objective: "Terminar o curso com distinção")
    sign_in_as @user
    get root_path
    assert_select ".dashboard-hero__objective blockquote", text: /Terminar o curso com distinção/
  end

  test "lists tasks, applications, reminders and notifications in their sections" do
    travel_to Time.utc(2030, 1, 15, 10, 0) do
      today = create_task(title: "Enviar CV", due_at: 4.hours.from_now, priority: 3)
      overdue = create_task(title: "Pagar propinas", due_at: 1.day.ago)
      upcoming = create_task(title: "Preparar exame", due_at: 3.days.from_now)
      create_task(title: "Muito longe", due_at: 20.days.from_now)
      create_task(title: "Arquivada", due_at: 2.hours.from_now, archived_at: Time.current)
      create_task(title: "Já feita", due_at: 2.hours.from_now, status: "completed", completed_at: Time.current)
      project = create_task(title: "Projeto final", status: "in_progress")
      create_task(title: "Sub 1", parent_task: project, status: "completed", completed_at: Time.current)
      create_task(title: "Sub 2", parent_task: project)
      create_task(users(:two), title: "Tarefa do Bruno", due_at: 2.hours.from_now)

      application = create_job_application(title: "Engenheira de Software", status: "applied")
      create_job_application(title: "Recusada", status: "rejected")
      reminder = upcoming.reminders.create!(remind_at: 1.day.from_now, channel: "email")
      @user.notifications.create!(notification_type: "task_due", notifiable: today, title: "Prazo a aproximar-se: Enviar CV")
      @user.notifications.create!(notification_type: "system", title: "Já lida", read_at: Time.current)

      sign_in_as @user
      get root_path

      assert_response :success
      assert_select ".stat--terracotta .stat__value", "1"
      assert_select ".stat--mustard .stat__value", "1"
      assert_select ".stat--olive .stat__value", "1"
      assert_select ".stat--charcoal .stat__value", "2" # "Já feita" + "Sub 1"

      assert_select "#dashboard-hoje", text: /Enviar CV/
      assert_select "#dashboard-atrasadas", text: /Pagar propinas/
      assert_select "#dashboard-proximos", text: /Preparar exame/
      assert_select "#dashboard-proximos", text: /Muito longe/, count: 0
      assert_select "#dashboard-em-curso", text: /Projeto final/
      assert_select "#dashboard-em-curso .progress[aria-valuenow='50']"
      assert_select "#dashboard-em-curso", text: /1 de 2 subtarefas/
      assert_select "form[action=?]", complete_task_path(today)
      assert_select "a[href=?]", job_applications_path
      assert_select "a[href=?]", job_application_path(application)
      assert_select ".badge--applied"
      assert_select ".list__title", text: "Recusada", count: 0
      assert_select "a[href=?]", task_path(reminder.task), text: "Preparar exame"
      assert_select ".dashboard-panel", text: /Prazo a aproximar-se: Enviar CV/
      assert_select ".dashboard-panel", text: /Já lida/, count: 0

      assert_no_match "Arquivada", response.body
      assert_no_match "Já feita", response.body
      assert_no_match "Tarefa do Bruno", response.body
      assert_select ".empty-state__title", text: "Um dia em branco, à tua espera", count: 0
    end
  end

  test "a task due exactly at midnight tomorrow is listed in the next 7 days" do
    travel_to Time.utc(2030, 1, 15, 10, 0) do # Lisbon is UTC in January
      create_task(title: "Entrega à meia-noite", due_at: Time.utc(2030, 1, 16, 0, 0))

      sign_in_as @user
      get root_path

      assert_select "#dashboard-proximos", text: /Entrega à meia-noite/
      assert_select "#dashboard-hoje", text: /Entrega à meia-noite/, count: 0
    end
  end

  test "counts only the tasks shown in each panel when there are more than fit" do
    travel_to Time.utc(2030, 1, 15, 10, 0) do
      (DashboardPresenter::LIST_LIMIT + 2).times { |i| create_task(title: "Atrasada #{i}", due_at: (i + 1).days.ago) }

      sign_in_as @user
      get root_path

      assert_select "#dashboard-atrasadas .list__item", DashboardPresenter::LIST_LIMIT
      assert_select "#dashboard-atrasadas .dashboard-panel__count", (DashboardPresenter::LIST_LIMIT + 2).to_s
      assert_select "#dashboard-atrasadas a[href=?]", tasks_path, text: "Ver todas"
    end
  end
end
