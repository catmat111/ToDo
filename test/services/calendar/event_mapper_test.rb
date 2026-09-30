require "test_helper"

class Calendar::EventMapperTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(timezone: "America/New_York")
  end

  test "uses starts_at..due_at and the user's time zone" do
    starts = Time.utc(2026, 10, 5, 13, 0)
    task = create_task(@user, title: "Exame", description: "Sala 2", starts_at: starts, due_at: starts + 2.hours)

    body = Calendar::EventMapper.call(task)

    assert_equal "Exame", body[:summary]
    assert_equal "Sala 2", body[:description]
    assert_equal "America/New_York", body[:start][:timeZone]
    assert_equal "2026-10-05T09:00:00-04:00", body[:start][:dateTime]
    assert_equal "2026-10-05T11:00:00-04:00", body[:end][:dateTime]
    assert_equal task.id.to_s, body.dig(:extendedProperties, :private, :todo_task_id)
  end

  test "only due_at gives a 30 minute event ending at the due time" do
    due = Time.utc(2026, 10, 5, 16, 0)
    body = Calendar::EventMapper.call(create_task(@user, due_at: due))

    assert_equal (due - 30.minutes).to_i, Time.iso8601(body[:start][:dateTime]).to_i
    assert_equal due.to_i, Time.iso8601(body[:end][:dateTime]).to_i
  end

  test "only starts_at gives a 30 minute event starting then" do
    starts = Time.utc(2026, 10, 5, 16, 0)
    body = Calendar::EventMapper.call(create_task(@user, starts_at: starts))

    assert_equal starts.to_i, Time.iso8601(body[:start][:dateTime]).to_i
    assert_equal (starts + 30.minutes).to_i, Time.iso8601(body[:end][:dateTime]).to_i
  end

  test "completed tasks get the check mark prefix" do
    task = create_task(@user, title: "Enviar CV", due_at: 1.day.from_now, status: "completed")
    assert_equal "✓ Enviar CV", Calendar::EventMapper.call(task)[:summary]
  end

  test "tasks without dates cannot be mapped" do
    assert_raises(ArgumentError) { Calendar::EventMapper.call(create_task(@user)) }
  end
end
