require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  test "reminder" do
    user = users(:one)
    task = create_task(user, title: "Entregar relatório", due_at: Time.utc(2030, 5, 10, 17, 30))
    notification = user.notifications.create!(notification_type: "reminder", notifiable: task,
                                              title: "Lembrete: Entregar relatório", body: "O prazo termina em breve.")

    mail = NotificationMailer.reminder(notification)

    assert_equal "Lembrete: Entregar relatório", mail.subject
    assert_equal [ user.email_address ], mail.to
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    assert_match "Olá Ana", html
    assert_match "O prazo termina em breve.", text
    assert_match "http://example.com/tasks/#{task.id}", text
    assert_match "http://example.com/tasks/#{task.id}", html
    # 17:30 UTC is 18:30 in Lisbon (summer time).
    assert_match "10/05/2030 às 18:30", text
  end

  test "reminder without a task links to notifications" do
    notification = users(:one).notifications.create!(notification_type: "reminder", title: "Lembrete: algo")

    mail = NotificationMailer.reminder(notification)

    assert_match "http://example.com/notifications", mail.text_part.body.to_s
  end
end
