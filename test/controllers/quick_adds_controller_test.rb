require "test_helper"
require_relative "../support/fake_ollama"

class QuickAddsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
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

  test "with the local LLM on, the sentence is read in the background" do
    ENV["OLLAMA_URL"] = "http://localhost:11434"
    AssistantReplyJob.client = FakeOllama.new(FakeOllama.call_tool("criar_tarefa", { "titulo" => "Ligar à mãe" }), FakeOllama.say("ok"))

    assert_enqueued_with(job: AssistantReplyJob) do
      post quick_add_path, params: { message: "ligar à mãe amanhã" }, as: :turbo_stream
    end
    assert_match "quickadd__dots", response.body

    perform_enqueued_jobs
    assert_equal [ "Ligar à mãe", Time.zone.tomorrow ], [ users(:one).tasks.last.title, users(:one).tasks.last.due_at.to_date ]
  ensure
    ENV.delete("OLLAMA_URL")
    AssistantReplyJob.client = nil
  end

  test "with Ollama down, the rules still add it" do
    AssistantReplyJob.client = Class.new { def chat(**) = raise(OllamaClient::Error, "off") }.new
    AssistantReplyJob.perform_now(users(:one).id, "Comprar pão", "assistant-x")
    assert_equal "Comprar pão", users(:one).tasks.last.title
  ensure
    AssistantReplyJob.client = nil
  end
end
