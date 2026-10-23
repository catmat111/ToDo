require "test_helper"
require_relative "../support/fake_ollama"

class TaskChatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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

  test "what the rules don't understand goes to the assistant in the background" do
    ENV["OLLAMA_URL"] = "http://localhost:11434"
    AssistantReplyJob.client = FakeOllama.new(
      FakeOllama.call_tool("adicionar_subtarefas", { "titulos" => [ "Ler", "Resumir" ] }), FakeOllama.say("ok")
    )

    assert_enqueued_with(job: AssistantReplyJob) do
      post task_chat_path(@task), params: { message: "divide isto em ler e resumir" }, as: :turbo_stream
    end
    assert_match "quickadd__dots", response.body
    assert_empty @task.subtasks

    perform_enqueued_jobs
    assert_equal %w[Ler Resumir], @task.subtasks.pluck(:title)
  ensure
    ENV.delete("OLLAMA_URL")
    AssistantReplyJob.client = nil
  end

  test "without the assistant, the rules answer as before" do
    post task_chat_path(@task), params: { message: "blá blá" }, as: :turbo_stream
    assert_match "Não percebi", response.body
    assert_no_enqueued_jobs only: AssistantReplyJob
  end

  test "the assistant being off is told in the chat" do
    AssistantReplyJob.client = Class.new { def chat(**) = raise(OllamaClient::Error, "off") }.new
    assert_nothing_raised { AssistantReplyJob.perform_now(users(:one).id, "olá", "assistant-x", @task.id) }
  ensure
    AssistantReplyJob.client = nil
  end
end
