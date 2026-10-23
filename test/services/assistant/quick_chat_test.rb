require "test_helper"
require_relative "../../support/fake_ollama"

module Assistant
  class QuickChatTest < ActiveSupport::TestCase
    setup do
      travel_to Time.zone.parse("2026-10-23 15:00") # a Friday
      @user = users(:one)
    end

    test "one sentence, several things, each with the date from its own part" do
      client = FakeOllama.new(
        { "role" => "assistant", "content" => "", "tool_calls" => [
          { "function" => { "name" => "criar_tarefa", "arguments" => { "titulo" => "Enviar CV" } } },
          { "function" => { "name" => "criar_evento", "arguments" => { "titulo" => "Jantar com a Ana", "quando" => "hoje", "local" => "Porto" } } }
        ] },
        FakeOllama.say("Feito!")
      )
      reply = QuickChat.call(@user, "tenho de enviar o CV até terça e marca jantar com a Ana sábado às 20h no Porto", client: client)

      assert reply.changed?
      task = @user.tasks.last
      assert_equal [ "Enviar CV", Time.zone.parse("2026-10-27").end_of_day.to_i ], [ task.title, task.due_at.to_i ]
      event = @user.events.last
      assert_equal [ "Jantar com a Ana", "Porto", Time.zone.parse("2026-10-24 20:00") ], [ event.title, event.location, event.starts_at ]
      assert_match "Adicionei a tarefa «Enviar CV»", reply.text
      assert_match "Marquei o evento «Jantar com a Ana»", reply.text
    end

    test "a task without a date is for today" do
      client = FakeOllama.new(FakeOllama.call_tool("criar_tarefa", { "titulo" => "comprar pão" }), FakeOllama.say("ok"))
      reply = QuickChat.call(@user, "comprar pão", client: client)
      assert_equal [ "Comprar pão", Time.zone.now.end_of_day.to_i ], [ @user.tasks.last.title, @user.tasks.last.due_at.to_i ]
      assert_match "para hoje", reply.text
    end

    test "an event needs a date" do
      client = FakeOllama.new(FakeOllama.call_tool("criar_evento", { "titulo" => "Reunião", "quando" => "" }), FakeOllama.say("Quando?"))
      assert_no_difference -> { Event.count } do
        assert_match "não percebi quando", QuickChat.call(@user, "reunião", client: client).text
      end
    end
  end
end
