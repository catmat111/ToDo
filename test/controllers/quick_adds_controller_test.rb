require "test_helper"

class QuickAddsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "adds a dated task from the chat" do
    post quick_add_path, params: { message: "Ligar ao banco amanhã às 10h" }, as: :turbo_stream

    assert_response :success
    task = users(:one).tasks.last
    assert_equal "Ligar ao banco", task.title
    assert_equal Time.zone.tomorrow, task.due_at.to_date
    assert_match "Adicionei", response.body
  end

  test "adds an event from the chat" do
    post quick_add_path, params: { message: "evento jantar sexta às 20h" }, as: :turbo_stream

    assert_response :success
    assert_equal "jantar", users(:one).events.last.title
    assert_match "Marquei o evento", response.body
  end
end
