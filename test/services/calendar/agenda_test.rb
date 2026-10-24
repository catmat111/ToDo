require "test_helper"

module Calendar
  class AgendaTest < ActiveSupport::TestCase
    setup do
      travel_to Time.zone.parse("2026-10-14 10:00") # a Wednesday
      @user = users(:one)
      @period = Period.new(view: "month", anchor: Date.new(2026, 10, 1), today: Time.zone.today)
    end

    def agenda = Agenda.new(user: @user, period: @period)

    test "an open task with a deadline spans from its start (or creation) to the deadline" do
      dated = create_task(@user, title: "Relatório", starts_at: Time.zone.parse("2026-10-12 09:00"), due_at: Time.zone.parse("2026-10-16 18:00"))
      created = create_task(@user, title: "Estudar", due_at: Time.zone.parse("2026-10-20 18:00")) # created today
      done = create_task(@user, title: "Feita", due_at: Time.zone.parse("2026-10-15 18:00"), status: "completed")

      spans = agenda.spans.index_by { |span| span.task.title }
      assert_equal [ Date.new(2026, 10, 12), Date.new(2026, 10, 16) ], [ spans["Relatório"].first_day, spans["Relatório"].last_day ]
      assert_equal Date.new(2026, 10, 14), spans["Estudar"].first_day
      assert_nil spans["Feita"] # done tasks stay on their day only

      assert_empty agenda.tasks_on(Date.new(2026, 10, 16)) # shown as the line, not twice
      assert_equal [ done ], agenda.tasks_on(Date.new(2026, 10, 15))
      assert_equal [ dated, created ], agenda.spans_on(Date.new(2026, 10, 15)).map(&:task)
    end

    test "a deadline after the month still draws its line inside it" do
      create_task(@user, title: "Longa", due_at: Time.zone.parse("2026-12-01 18:00"))
      assert_equal [ "Longa" ], agenda.spans.map { |span| span.task.title }
    end

    test "lines get lanes that don't overlap within a week" do
      create_task(@user, title: "A", starts_at: Time.zone.parse("2026-10-12 09:00"), due_at: Time.zone.parse("2026-10-14 18:00"))
      create_task(@user, title: "B", starts_at: Time.zone.parse("2026-10-13 09:00"), due_at: Time.zone.parse("2026-10-17 18:00"))
      create_task(@user, title: "C", starts_at: Time.zone.parse("2026-10-15 09:00"), due_at: Time.zone.parse("2026-10-16 18:00"))

      lanes = agenda.lanes((Date.new(2026, 10, 12)..Date.new(2026, 10, 18)).to_a)
      assert_equal [ %w[A C], %w[B] ], lanes.map { |lane| lane.map { |span| span.task.title } }
    end
  end
end
