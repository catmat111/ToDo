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

  test "the backlog lists each tag with its open tasks, undated ones too" do
    user = users(:one)
    sign_in_as user
    study = user.tags.create!(name: "Estudo")
    user.tags.create!(name: "Casa")
    create_task(user, title: "Angular", tag_ids: [ study.id ])
    create_task(user, title: "React", tag_ids: [ study.id ], due_at: 2.days.from_now)
    create_task(user, title: "Feita", tag_ids: [ study.id ], status: "completed")

    get root_path
    assert_select ".home-backlog .home-backlog__group", 2
    assert_select ".home-backlog__group[open]", 1 # Casa has nothing, so it starts closed
    assert_select ".home-backlog__group[open] .home-backlog__link", count: 2
    assert_select ".home-backlog__link", text: "React" # dated first
    assert_select ".home-backlog__link", text: "Feita", count: 0
  end

  test "adding from a tag's backlog puts the task in that tag, without a date" do
    sign_in_as users(:one)
    study = users(:one).tags.create!(name: "Estudo")
    post tasks_path, params: { return_to: "home", task: { title: "Vue", tag_ids: [ study.id ] } }

    assert_redirected_to root_path
    assert_equal "«Vue» adicionada a «Estudo».", flash[:notice]
    task = users(:one).tasks.last
    assert_equal [ [ study ], nil ], [ task.tags.to_a, task.due_at ]
  end

  test "shows the goal from the profile, quietly, when there is one" do
    sign_in_as users(:one)
    get root_path
    assert_select ".home__objective", 0

    users(:one).update!(objective: "Encontrar emprego e passar ao mestrado")
    get root_path
    assert_select ".home__objective a[href=?]", profile_path, text: "Encontrar emprego e passar ao mestrado"
  end

  test "dragging a backlog task onto today gives it today as its deadline" do
    sign_in_as users(:one)
    study = users(:one).tags.create!(name: "Estudo")
    task = create_task(users(:one), title: "Angular", tag_ids: [ study.id ], starts_at: 3.days.from_now)

    patch plan_task_path(task), params: { to: "today" }, as: :turbo_stream
    assert_response :success
    assert_match %(action="refresh"), response.body
    assert_equal Time.zone.today, task.reload.due_at.to_date
    assert_nil task.starts_at # a later start would be after the new deadline
  end

  test "dragging a today task onto a tag removes the deadline and adds the tag" do
    sign_in_as users(:one)
    study = users(:one).tags.create!(name: "Estudo")
    task = create_task(users(:one), title: "Tibco", due_at: Time.current.end_of_day)

    patch plan_task_path(task), params: { to: "backlog", tag_id: study.id }, as: :turbo_stream
    assert_nil task.reload.due_at
    assert_equal [ study ], task.tags.to_a

    get root_path
    assert_select ".home-backlog__group[data-tag-id=?] .home-backlog__link", study.id.to_s, text: "Tibco"
    assert_select "#home-today-list li", 0
  end

  test "can't drag onto someone else's tag or move someone else's task" do
    sign_in_as users(:one)
    task = create_task(users(:one), title: "Minha")
    other_tag = users(:two).tags.create!(name: "Dele")
    patch plan_task_path(task), params: { to: "backlog", tag_id: other_tag.id }, as: :turbo_stream
    assert_response :not_found

    patch plan_task_path(create_task(users(:two))), params: { to: "today" }, as: :turbo_stream
    assert_response :not_found
  end
end
