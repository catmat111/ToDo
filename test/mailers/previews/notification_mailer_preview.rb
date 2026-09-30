# Preview all emails at http://localhost:3000/rails/mailers/notification_mailer
class NotificationMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/notification_mailer/reminder
  def reminder
    notification = Notification.of_type("reminder").where(notifiable_type: "Task").last || sample_notification
    NotificationMailer.reminder(notification)
  end

  private
    # Unsaved sample so the preview works on an empty database.
    def sample_notification
      user = User.first || User.new(name: "Ana Silva", email_address: "ana@example.com")
      task = Task.new(id: 1, user: user, title: "Entregar relatório final", priority: 2, due_at: 1.day.from_now.change(hour: 18))
      Notification.new(user: user, notifiable: task, notification_type: "reminder",
                       title: "Lembrete: #{task.title}", body: "O prazo termina amanhã às 18:00.")
    end
end
