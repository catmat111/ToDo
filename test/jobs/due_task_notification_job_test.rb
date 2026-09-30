require "test_helper"

class DueTaskNotificationJobTest < ActiveJob::TestCase
  test "notifies once per open task due in the next 24 hours" do
    due_soon = create_task(title: "Exame de Física", due_at: 3.hours.from_now)
    create_task(due_at: 3.days.from_now)
    create_task(due_at: 2.hours.ago)
    create_task(due_at: 5.hours.from_now, status: "completed", completed_at: Time.current)
    create_task(due_at: 5.hours.from_now, archived_at: Time.current)
    create_task(users(:two), due_at: 6.hours.from_now)

    assert_difference -> { Notification.of_type("task_due").count }, 2 do
      DueTaskNotificationJob.perform_now
    end

    notification = users(:one).notifications.of_type("task_due").sole
    assert_equal due_soon, notification.notifiable
    assert_equal "Prazo a aproximar-se: Exame de Física", notification.title
    assert_match "Esta tarefa termina", notification.body
    assert_equal 1, users(:two).notifications.of_type("task_due").count
  end

  test "is idempotent" do
    create_task(due_at: 3.hours.from_now)

    assert_difference -> { Notification.count }, 1 do
      DueTaskNotificationJob.perform_now
      DueTaskNotificationJob.perform_now
    end
  end

  test "reminder notifications do not prevent the due notification" do
    task = create_task(due_at: 3.hours.from_now)
    users(:one).notifications.create!(notification_type: "reminder", notifiable: task, title: "Lembrete: #{task.title}")

    assert_difference -> { Notification.of_type("task_due").count }, 1 do
      DueTaskNotificationJob.perform_now
    end
  end

  test "an orphaned task_due notification does not block other tasks" do
    orphan = users(:one).notifications.create!(notification_type: "task_due", title: "Tarefa apagada")
    orphan.update_columns(notifiable_type: "Task", notifiable_id: nil)
    create_task(due_at: 3.hours.from_now)

    assert_difference -> { Notification.of_type("task_due").count }, 1 do
      DueTaskNotificationJob.perform_now
    end
  end
end
