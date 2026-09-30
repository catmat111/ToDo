require "test_helper"

module Tasks
  class FilterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
    end

    def titles(params = {})
      Filter.new(@user, params).tasks.map(&:title)
    end

    test "defaults to root-level, non-archived tasks of the user" do
      root = create_task(title: "Raiz")
      create_task(title: "Filha", parent_task: root)
      create_task(title: "Arquivada", archived_at: Time.current)
      create_task(users(:two), title: "Alheia")

      assert_equal [ "Raiz" ], titles
      assert_equal [ "Filha", "Raiz" ], titles(subtasks: "1").sort
      assert_equal [ "Arquivada" ], titles(archived: "1")
    end

    test "text search is case-insensitive over title and description, at every level" do
      root = create_task(title: "Relatório FINAL")
      create_task(title: "Passo", description: "rever o relatório com calma", parent_task: root)
      create_task(title: "Outra coisa")

      assert_equal [ "Passo", "Relatório FINAL" ], titles(q: "RELAT").sort
      assert_equal [ "Relatório FINAL" ], titles(q: "final")
      assert_includes titles(q: "calma"), "Passo"
    end

    test "search wildcards are escaped" do
      create_task(title: "100% feito")
      create_task(title: "Nada")
      assert_equal [ "100% feito" ], titles(q: "%")
    end

    test "filters by status, type and priority" do
      create_task(title: "A", task_type: "exam", priority: 3)
      create_task(title: "B", status: "completed")
      create_task(title: "C", status: "in_progress")

      assert_equal [ "B" ], titles(status: "completed")
      assert_equal [ "A", "C" ], titles(status: "open").sort
      assert_equal [ "A" ], titles(task_type: "exam")
      assert_equal [ "A" ], titles(priority: "3")
      assert_equal 3, titles(status: "bogus").size
    end

    test "filters by one of the user's tags and ignores other users' tags" do
      tag = @user.tags.create!(name: "Trabalho")
      foreign = users(:two).tags.create!(name: "Trabalho")
      create_task(title: "Etiquetada", tags: [ tag ])
      create_task(title: "Simples")

      assert_equal [ "Etiquetada" ], titles(tag_id: tag.id.to_s)
      assert_equal 2, titles(tag_id: foreign.id.to_s).size
    end

    test "filters by due date" do
      travel_to Time.zone.local(2026, 9, 30, 12, 0) do
        create_task(title: "Hoje", due_at: Time.zone.local(2026, 9, 30, 18, 0))
        create_task(title: "Atrasada", due_at: Time.zone.local(2026, 9, 28, 9, 0))
        create_task(title: "Domingo", due_at: Time.zone.local(2026, 10, 4, 9, 0))
        create_task(title: "Longe", due_at: Time.zone.local(2026, 12, 1, 9, 0))
        create_task(title: "Sem data")

        assert_equal [ "Hoje" ], titles(due: "today")
        assert_equal [ "Atrasada" ], titles(due: "overdue")
        assert_equal [ "Atrasada", "Domingo", "Hoje" ], titles(due: "week").sort
        assert_equal [ "Sem data" ], titles(due: "none")
      end
    end

    test "sorts by due date with open tasks first, by title and by priority" do
      create_task(title: "b", due_at: 2.days.from_now)
      create_task(title: "A", due_at: 1.day.from_now, priority: 1)
      create_task(title: "c", priority: 3)
      create_task(title: "Feita", due_at: 1.hour.from_now, status: "completed")

      assert_equal %w[A b c Feita], titles
      assert_equal %w[A b c Feita], titles(sort: "title")
      assert_equal %w[c A b Feita], titles(sort: "priority")
    end

    test "paginates 50 per page" do
      now = Time.current
      rows = Array.new(Filter::PER_PAGE + 3) do |i|
        { user_id: @user.id, title: "T#{i}", task_type: "other", status: "pending", created_at: now, updated_at: now }
      end
      Task.insert_all!(rows)

      first = Filter.new(@user, {})
      assert_equal Filter::PER_PAGE, first.tasks.size
      assert first.next_page?
      assert_not first.previous_page?

      second = Filter.new(@user, page: "2")
      assert_equal 3, second.tasks.size
      assert_not second.next_page?
      assert second.previous_page?
    end

    test "to_params only keeps sanitized, non-default values" do
      filter = Filter.new(@user, q: " x ", status: "nope", sort: "due", subtasks: "1", host: "evil.example")
      assert_equal({ q: "x", subtasks: "1" }, filter.to_params)
      assert filter.active?
      assert_not Filter.new(@user, {}).active?
    end
  end
end
