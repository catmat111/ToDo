require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "finds tasks, applications and companies case-insensitively, only the user's own" do
    create_task(@user, title: "Preparar entrevista ACME")
    create_job_application(@user, title: "Dev Júnior", company_name: "Acme Lda")
    create_task(users(:two), title: "Tarefa ACME do Bruno")

    get search_path(q: "acme")

    assert_response :success
    assert_select "#search-tasks", text: /Tarefas/
    assert_select ".list__title", text: /Preparar entrevista/
    assert_select ".list__title", text: /Dev Júnior/
    assert_select ".list__title", text: /Bruno/, count: 0
  end

  test "asks for at least 2 letters" do
    get search_path(q: "a")
    assert_select ".page-header__subtitle", text: /pelo menos 2 letras/
  end
end
