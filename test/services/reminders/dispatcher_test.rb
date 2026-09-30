require "test_helper"

class Reminders::DispatcherTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  # Simulates a delivery failure (e.g. the database or mailer being down).
  class FailingDispatcher < Reminders::Dispatcher
    private
      def deliver(*)
        raise ActiveRecord::StatementInvalid, "database is locked password=hunter2"
      end
  end

  setup do
    @task = create_task(title: "Entregar relatório", due_at: 2.hours.from_now)
  end

  def due_reminder(task = @task, channel: "in_app")
    reminder = task.reminders.create!(remind_at: 1.hour.from_now, channel: channel)
    reminder.update_column(:remind_at, 1.minute.ago)
    reminder
  end

  test "creates exactly one notification even when run twice" do
    reminder = due_reminder

    result = nil
    assert_difference -> { Notification.count }, 1 do
      result = Reminders::Dispatcher.call
      Reminders::Dispatcher.call
    end
    assert_equal 1, result.delivered

    notification = Notification.last
    assert_equal users(:one), notification.user
    assert_equal @task, notification.notifiable
    assert_equal "reminder", notification.notification_type
    assert_equal "Lembrete: Entregar relatório", notification.title
    assert_match "O prazo termina a", notification.body
    assert reminder.reload.sent?
  end

  test "does not deliver reminders that are not due yet" do
    @task.reminders.create!(remind_at: 30.minutes.from_now)
    assert_no_difference -> { Notification.count } do
      Reminders::Dispatcher.call
    end
  end

  test "marks reminders of completed, cancelled or archived tasks as sent without notifying" do
    completed = due_reminder
    @task.update!(status: "completed", completed_at: Time.current)

    cancelled_task = create_task(due_at: 1.day.from_now)
    cancelled = due_reminder(cancelled_task)
    cancelled_task.update!(status: "cancelled")

    archived_task = create_task(due_at: 1.day.from_now)
    archived = due_reminder(archived_task)
    archived_task.update!(archived_at: Time.current)

    result = nil
    assert_no_difference -> { Notification.count } do
      result = Reminders::Dispatcher.call
    end
    assert_equal 3, result.skipped
    assert [ completed, cancelled, archived ].all? { |r| r.reload.sent? }
  end

  test "email channel enqueues the reminder email" do
    due_reminder(channel: "email")

    assert_enqueued_emails 1 do
      Reminders::Dispatcher.call
    end
  end

  test "in-app channel does not send email" do
    due_reminder
    assert_no_enqueued_emails do
      Reminders::Dispatcher.call
    end
  end

  test "failure releases the claim, counts the attempt and keeps the error without secrets" do
    reminder = due_reminder

    result = nil
    assert_no_difference -> { Notification.count } do
      result = FailingDispatcher.call
    end
    assert_equal 1, result.failed

    reminder.reload
    assert_nil reminder.sent_at
    assert_equal 1, reminder.attempts
    assert_match "database is locked", reminder.last_error
    assert_not_includes reminder.last_error, "hunter2"
    assert_includes Reminder.due, reminder, "must be picked up again"
  end

  test "stops retrying after MAX_ATTEMPTS" do
    reminder = due_reminder
    Reminder::MAX_ATTEMPTS.times { FailingDispatcher.call }

    assert_equal Reminder::MAX_ATTEMPTS, reminder.reload.attempts
    assert reminder.failed?
    assert_not_includes Reminder.due, reminder

    assert_no_difference -> { Notification.count } do
      Reminders::Dispatcher.call
    end
    assert_equal Reminder::MAX_ATTEMPTS, reminder.reload.attempts
  end

  test "a later successful run clears the last error" do
    reminder = due_reminder
    FailingDispatcher.call

    assert_difference -> { Notification.count }, 1 do
      Reminders::Dispatcher.call
    end
    reminder.reload
    assert reminder.sent?
    assert_nil reminder.last_error
  end
end
