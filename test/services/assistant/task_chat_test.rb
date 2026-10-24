require "test_helper"
require_relative "../../support/fake_ollama"

module Assistant
  class TaskChatTest < ActiveSupport::TestCase
    setup do
      travel_to Time.zone.parse("2026-10-23 15:00") # a Friday
      @task = create_task(title: "Estudar python", due_at: Time.zone.parse("2026-10-27 18:00"))
    end

    def chat(*replies, message: "faz coisas")
      client = FakeOllama.new(*replies)
      [ TaskChat.call(@task, message, client: client), client ]
    end

    test "runs the tools the model asks for and reports their real results" do
      reply, client = chat(
        FakeOllama.call_tool("adicionar_subtarefas", { "titulos" => [ "Ler", "Resumir" ] }),
        FakeOllama.call_tool("adicionar_lembrete", { "data_hora" => "na véspera às 10h" }),
        FakeOllama.say("Fiz tudo e mais alguma coisa!")
      )

      assert reply.changed?
      @task.reload
      assert_equal %w[Ler Resumir], @task.subtasks.pluck(:title)
      assert_equal Time.zone.parse("2026-10-26 10:00"), @task.reminders.first.remind_at
      assert_match "Criei 2 subtarefa(s)", reply.text
      assert_no_match "mais alguma coisa", reply.text # the model's own summary isn't trusted
      assert_equal "tool", client.requests.last.last[:role]
    end

    test "the app reads the dates from the user's words" do
      chat(FakeOllama.call_tool("mudar_prazo", { "data_hora" => "sexta às 15h" }), FakeOllama.say("ok"))
      assert_equal Time.zone.parse("2026-10-30 15:00"), @task.reload.due_at

      chat(FakeOllama.call_tool("mudar_prazo", { "data_hora" => "2026-11-02" }), FakeOllama.say("ok"))
      assert_equal Time.zone.parse("2026-11-02").end_of_day.to_i, @task.reload.due_at.to_i
    end

    test "arguments sent under the wrong tool go to the tool they fit" do
      chat(FakeOllama.call_tool("mudar_prioridade", { "nomes" => [ "estudo" ] }), FakeOllama.say("ok"))
      assert_equal [ "Estudo" ], @task.tags.pluck(:name)
      assert_equal 0, @task.reload.priority
    end

    test "a repeated call runs once" do
      call = FakeOllama.call_tool("adicionar_subtarefas", { "titulos" => [ "Ler" ] })
      chat(call, call, FakeOllama.say("ok"))
      assert_equal 1, @task.reload.subtasks.count
    end

    test "a question from the model is passed on and changes nothing" do
      reply, = chat(FakeOllama.say("A que horas queres o lembrete?"))
      assert_equal "A que horas queres o lembrete?", reply.text
      assert_not reply.changed?
    end

    test "bad tool input becomes an error for the model, not an exception" do
      reply, = chat(FakeOllama.call_tool("adicionar_lembrete", { "data_hora" => "quando calhar" }), FakeOllama.say("Desculpa."))
      assert_match "não percebi a data", reply.text
      assert_empty @task.reminders
    end

    test "it cannot delete" do
      reply, = chat(FakeOllama.call_tool("apagar_tarefa", {}), FakeOllama.say("Apaguei."))
      assert Task.exists?(@task.id)
      assert_match "ferramenta desconhecida", reply.text
    end
  end
end
