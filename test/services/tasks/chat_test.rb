require "test_helper"

module Tasks
  class ChatTest < ActiveSupport::TestCase
    setup do
      travel_to Time.zone.parse("2026-10-13 15:00") # a Tuesday
      @task = create_task(title: "Estudar python", due_at: Time.zone.parse("2026-10-20 18:00"))
    end

    def say(message)
      Chat.call(@task, message)
    end

    test "adds subtasks, several at once" do
      reply = say("subtarefas Rever listas, Fazer exercícios")

      assert reply.ok?
      assert_equal [ "Rever listas", "Fazer exercícios" ], @task.subtasks.pluck(:title)
    end

    test "adds a reminder at a given time or relative to the due date" do
      assert say("lembra-me amanhã às 9h").ok?
      assert say("lembrete 1 dia antes por email").ok?

      reminders = @task.reminders.reload
      assert_equal Time.zone.parse("2026-10-14 09:00"), reminders.first.remind_at
      assert_equal [ Time.zone.parse("2026-10-19 18:00"), "email" ], [ reminders.last.remind_at, reminders.last.channel ]
    end

    test "asks when a reminder has no time" do
      reply = say("lembra-me")
      assert_not reply.ok?
      assert_match "Quando?", reply.text
    end

    test "adds and removes tags, reusing existing ones" do
      existing = users(:one).tags.create!(name: "Faculdade")
      assert say("etiqueta faculdade, Python").ok?
      assert_equal %w[Faculdade Python], @task.tags.reload.map(&:name).sort
      assert_equal existing, @task.tags.find_by(name: "Faculdade")

      assert say("tirar etiqueta python").ok?
      assert_equal %w[Faculdade], @task.tags.reload.map(&:name)
    end

    test "changes due date, priority, title and description" do
      assert say("prazo sexta às 18h").ok?
      assert_equal Time.zone.parse("2026-10-16 18:00"), @task.reload.due_at

      assert say("prazo 25/10").ok?
      assert_equal Time.zone.parse("2026-10-25").end_of_day.to_i, @task.reload.due_at.to_i

      assert say("prioridade alta").ok?
      assert_equal 2, @task.reload.priority

      assert say("renomear para Estudar Ruby").ok?
      assert_equal "Estudar Ruby", @task.reload.title

      assert say("nota ver capítulo 4").ok?
      assert_equal "ver capítulo 4", @task.reload.description

      assert say("sem prazo").ok?
      assert_nil @task.reload.due_at
    end

    test "changes status" do
      assert say("iniciar").ok?
      assert @task.reload.in_progress?
      assert say("concluir").ok?
      assert @task.reload.completed?
    end

    test "sets and removes a recurrence" do
      assert say("repetir a cada 2 semanas").ok?
      assert_equal [ "weekly", 2 ], [ @task.recurrence.frequency, @task.recurrence.interval ]

      assert say("deixar de repetir").ok?
      assert_nil @task.reload.recurrence
    end

    test "shares with someone by email" do
      assert_difference -> { Share.count }, 1 do
        assert say("partilhar com two@example.com: vês isto?").ok?
      end
      assert_equal "vês isto?", Share.last.message
    end

    test "saves a link and a dependency" do
      blocker = create_task(title: "Instalar python")
      assert say("link https://docs.python.org tutorial").ok?
      assert_equal "https://docs.python.org", @task.links.last.url

      assert say("depende de instalar").ok?
      assert_equal [ blocker ], @task.blockers.to_a
    end

    test "never deletes and explains when it doesn't understand" do
      assert_not say("apagar").ok?
      assert Task.exists?(@task.id)

      reply = say("blá blá")
      assert_not reply.ok?
      assert_not reply.changed?
      assert_match "ajuda", reply.text
    end
  end
end
