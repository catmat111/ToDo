require "test_helper"

class QuickAddTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.parse("2026-10-13 15:00") # a Tuesday
    @user = users(:one)
  end

  test "a task without a date is for today" do
    reply = QuickAdd.call(@user, "Comprar pão")

    assert reply.ok?
    assert_equal [ "Comprar pão", Time.zone.now.end_of_day.to_i ], [ reply.record.title, reply.record.due_at.to_i ]
  end

  test "takes the date and time out of the title" do
    task = QuickAdd.call(@user, "Ligar ao banco amanhã às 10h").record
    assert_equal [ "Ligar ao banco", Time.zone.parse("2026-10-14 10:00") ], [ task.title, task.due_at ]

    task = QuickAdd.call(@user, "Entregar relatório sexta").record
    assert_equal [ "Entregar relatório", Time.zone.parse("2026-10-16").end_of_day.to_i ], [ task.title, task.due_at.to_i ]

    task = QuickAdd.call(@user, "Pagar renda até 30/10").record
    assert_equal "Pagar renda", task.title
    assert_equal Date.new(2026, 10, 30), task.due_at.to_date
  end

  test "keeps numbers that aren't dates" do
    assert_equal "Ler 2 capítulos", QuickAdd.call(@user, "Ler 2 capítulos").record.title
  end

  test "creates an event, with an hour or for the whole day" do
    event = QuickAdd.call(@user, "evento Jantar com a Ana sábado às 20h").record
    assert_kind_of Event, event
    assert_equal [ "Jantar com a Ana", Time.zone.parse("2026-10-17 20:00"), Time.zone.parse("2026-10-17 21:00") ],
                 [ event.title, event.starts_at, event.ends_at ]

    event = QuickAdd.call(@user, "evento Feriado 8/12").record
    assert event.all_day?
    assert_equal Date.new(2026, 12, 8), event.first_day
  end

  test "an event needs a date" do
    reply = QuickAdd.call(@user, "evento jantar")
    assert_not reply.ok?
    assert_match "Quando", reply.text
  end
end
