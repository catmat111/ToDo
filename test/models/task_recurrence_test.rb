require "test_helper"

class TaskRecurrenceTest < ActiveSupport::TestCase
  setup do
    @task = create_task
    @time = Time.zone.local(2026, 1, 31, 9, 0)
  end

  test "requires a known frequency and a positive interval" do
    recurrence = TaskRecurrence.new(task: @task, frequency: "hourly", interval: 0)
    assert_not recurrence.valid?
    assert recurrence.errors[:frequency].any?
    assert recurrence.errors[:interval].any?
  end

  test "next_time advances by frequency and interval" do
    assert_equal @time + 1.day, TaskRecurrence.new(frequency: "daily", interval: 1).next_time(@time)
    assert_equal @time + 2.weeks, TaskRecurrence.new(frequency: "weekly", interval: 2).next_time(@time)
    assert_equal Time.zone.local(2026, 2, 28, 9, 0), TaskRecurrence.new(frequency: "monthly", interval: 1).next_time(@time)
    assert_equal @time + 1.year, TaskRecurrence.new(frequency: "yearly", interval: 1).next_time(@time)
  end

  test "next_time respects ends_at" do
    recurrence = TaskRecurrence.new(frequency: "weekly", interval: 1, ends_at: @time + 3.days)
    assert_nil recurrence.next_time(@time)
    recurrence.ends_at = @time + 7.days
    assert_equal @time + 7.days, recurrence.next_time(@time)
  end

  test "next_time of nil is nil" do
    assert_nil TaskRecurrence.new(frequency: "daily", interval: 1).next_time(nil)
  end

  test "a task has at most one recurrence" do
    TaskRecurrence.create!(task: @task, frequency: "daily", interval: 1)
    assert_raises(ActiveRecord::RecordNotUnique) do
      TaskRecurrence.create!(task: @task, frequency: "weekly", interval: 1)
    end
  end

  test "frequency labels" do
    assert_equal %w[Diária Semanal Mensal Anual], TaskRecurrence::FREQUENCIES.map { |f| TaskRecurrence.frequency_label(f) }
  end
end
