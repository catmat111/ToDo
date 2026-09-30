require "test_helper"

class ReminderTest < ActiveSupport::TestCase
  setup do
    @task = create_task(due_at: 3.days.from_now)
  end

  test "valid with a future time and a known channel" do
    reminder = @task.reminders.build(remind_at: 1.day.from_now, channel: "email")
    assert reminder.valid?
    assert_equal "Email", reminder.channel_label
  end

  test "defaults to the in-app channel" do
    assert_equal "in_app", @task.reminders.build(remind_at: 1.day.from_now).channel
  end

  test "requires remind_at" do
    reminder = @task.reminders.build(remind_at: nil)
    assert_not reminder.valid?
    assert_includes reminder.errors[:remind_at], "tem de ser indicada"
  end

  test "rejects an unknown channel" do
    reminder = @task.reminders.build(remind_at: 1.day.from_now, channel: "sms")
    assert_not reminder.valid?
    assert reminder.errors.added?(:channel, :inclusion, value: "sms")
  end

  test "rejects a time in the past on create" do
    reminder = @task.reminders.build(remind_at: 1.minute.ago)
    assert_not reminder.valid?
    assert_includes reminder.errors[:remind_at], "tem de ser no futuro"
  end

  test "rejects duplicates for the same task, time and channel" do
    at = 1.day.from_now.change(sec: 0)
    @task.reminders.create!(remind_at: at)
    duplicate = @task.reminders.build(remind_at: at)
    assert_not duplicate.valid?
    assert duplicate.errors.added?(:remind_at, :taken, value: duplicate.remind_at)
    assert @task.reminders.build(remind_at: at, channel: "email").valid?, "another channel is fine"
  end

  test "cannot be created for a closed task" do
    @task.update!(status: "completed", completed_at: Time.current)
    reminder = @task.reminders.build(remind_at: 1.day.from_now)
    assert_not reminder.valid?
    assert reminder.errors[:task].any?
  end

  test "due only includes unsent reminders under the attempt limit" do
    due = @task.reminders.create!(remind_at: 1.hour.from_now)
    due.update_column(:remind_at, 5.minutes.ago)
    later = @task.reminders.create!(remind_at: 2.hours.from_now)
    sent = @task.reminders.create!(remind_at: 3.hours.from_now)
    sent.update_columns(remind_at: 10.minutes.ago, sent_at: 9.minutes.ago)
    exhausted = @task.reminders.create!(remind_at: 4.hours.from_now)
    exhausted.update_columns(remind_at: 10.minutes.ago, attempts: Reminder::MAX_ATTEMPTS)

    assert_equal [ due ], Reminder.due.to_a
    assert_includes Reminder.upcoming, later
    assert exhausted.reload.failed?
    assert_includes Reminder.failed, exhausted
  end

  test "claim! succeeds only once" do
    reminder = @task.reminders.create!(remind_at: 1.hour.from_now)
    assert reminder.claim!
    assert reminder.sent?
    assert_not Reminder.find(reminder.id).claim!
  end

  test "record_failure! releases the claim and stores a sanitized error" do
    reminder = @task.reminders.create!(remind_at: 1.hour.from_now)
    reminder.claim!
    reminder.record_failure!(RuntimeError.new("SMTP falhou token=abc123 #{'x' * 600}"))

    assert_nil reminder.sent_at
    assert_equal 1, reminder.attempts
    assert_includes reminder.last_error, "RuntimeError"
    assert_includes reminder.last_error, "token=[FILTERED]"
    assert_not_includes reminder.last_error, "abc123"
    assert_operator reminder.last_error.length, :<=, Reminder::ERROR_MAX_LENGTH
  end
end
