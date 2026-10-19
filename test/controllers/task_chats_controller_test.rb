require "test_helper"

class TaskChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @task = create_task(title: "Estudar python")
    sign_in_as users(:one)
  end

  test "answers in the chat and refreshes the task page" do
    post task_chat_path(@task), params: { message: "subtarefa Rever listas" }, as: :turbo_stream

    assert_response :success
    assert_match "Adicionei a subtarefa", response.body
    assert_match %(target="task_page"), response.body
    assert_equal [ "Rever listas" ], @task.subtasks.pluck(:title)
  end

  test "doesn't refresh the page when nothing changed" do
    post task_chat_path(@task), params: { message: "ajuda" }, as: :turbo_stream

    assert_response :success
    assert_no_match %(target="task_page"), response.body
  end

  test "only works on the user's own tasks" do
    other = create_task(users(:two))
    post task_chat_path(other), params: { message: "concluir" }, as: :turbo_stream

    assert_response :not_found
    assert other.reload.pending?
  end

  test "the task page shows the task chat" do
    get task_path(@task)

    assert_select "form[action=?] input[name=message]", task_chat_path(@task)
    assert_select "#quickadd-title", "Nesta tarefa"
  end
end
