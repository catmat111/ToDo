require "test_helper"

class ReminderDispatchJobTest < ActiveJob::TestCase
  test "runs on the default queue" do
    assert_equal "default", ReminderDispatchJob.new.queue_name
  end

  test "dispatches due reminders" do
    task = create_task(due_at: 1.day.from_now)
    reminder = task.reminders.create!(remind_at: 1.hour.from_now)
    reminder.update_column(:remind_at, 1.minute.ago)

    assert_difference -> { users(:one).notifications.count }, 1 do
      ReminderDispatchJob.perform_now
    end
    assert reminder.reload.sent?
  end
end
