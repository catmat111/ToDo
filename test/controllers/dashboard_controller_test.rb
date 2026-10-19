require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  TODAY = "section[aria-labelledby=home-today]".freeze
  NEXT = "section[aria-labelledby=home-next]".freeze

  setup do
    @user = users(:one)
  end

  test "requires authentication" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "renders the essentials when the user has no data" do
    sign_in_as @user
    get root_path

    assert_response :success
    assert_select "h1", text: /(Bom dia|Boa tarde|Boa noite), Ana/
    assert_select ".quickadd__fab"
    assert_select ".quickadd__form input[name='message']"
    assert_select ".home__empty", text: /Nada para hoje/
    assert_select NEXT, count: 0
    assert_select ".home__footnote", count: 0
  end

  test "greets according to the hour in the user's time zone" do
    # Sign in inside each time jump: sessions expire after 30 idle days.
    travel_to(Time.utc(2030, 1, 15, 9, 0)) { sign_in_as @user; get root_path; assert_select "h1", "Bom dia, Ana." }
    travel_to(Time.utc(2030, 1, 15, 15, 0)) { sign_in_as @user; get root_path; assert_select "h1", "Boa tarde, Ana." }
    travel_to(Time.utc(2030, 1, 15, 22, 0)) { sign_in_as @user; get root_path; assert_select "h1", "Boa noite, Ana." }
  end

  test "today lists overdue and today's tasks; next lists the coming days" do
    travel_to Time.utc(2030, 1, 15, 10, 0) do
      today = create_task(title: "Enviar CV", due_at: 4.hours.from_now)
      create_task(title: "Pagar propinas", due_at: 1.day.ago)
      create_task(title: "Preparar exame", due_at: 3.days.from_now)
      create_task(title: "Arquivada", due_at: 2.hours.from_now, archived_at: Time.current)
      create_task(title: "Já feita", due_at: 2.hours.from_now, status: "completed", completed_at: Time.current)
      create_task(users(:two), title: "Tarefa do Bruno", due_at: 2.hours.from_now)
      create_job_application(title: "Engenheira de Software", status: "applied")
      create_job_application(title: "Recusada", status: "rejected")

      sign_in_as @user
      get root_path

      assert_select TODAY, text: /Enviar CV/
      assert_select TODAY, text: /Pagar propinas/
      assert_select "#{TODAY} .home-task--overdue", text: /Pagar propinas/
      assert_select NEXT, text: /Preparar exame/
      assert_select "body", text: /Arquivada|Já feita|Tarefa do Bruno/, count: 0
      assert_select "form[action=?]", complete_task_path(today)
      assert_select ".home__footnote a[href=?]", job_applications_path, text: /1 candidatura em curso/
    end
  end

  test "quick add creates a task due today and returns home" do
    sign_in_as @user
    assert_difference -> { @user.tasks.count } => 1 do
      post tasks_path, params: { return_to: "home", task: { title: "Ligar ao banco", due_at: Time.current.end_of_day.strftime("%Y-%m-%dT%H:%M") } }
    end
    assert_redirected_to root_path
    follow_redirect!
    assert_select TODAY, text: /Ligar ao banco/
  end

  test "the quick-add chat answers with turbo streams" do
    sign_in_as @user
    assert_difference -> { @user.tasks.count } => 1 do
      post tasks_path, params: { return_to: "chat", task: { title: "Comprar pão", due_at: Time.current.end_of_day.strftime("%Y-%m-%dT%H:%M") } },
                       headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_match 'target="quickadd_messages"', response.body
    assert_match "Comprar pão", response.body
    assert_match 'target="home-today-list"', response.body
  end
end
