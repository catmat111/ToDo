class NotificationMailer < ApplicationMailer
  # NotificationMailer.reminder(notification).deliver_later
  def reminder(notification)
    @notification = notification
    @user = notification.user
    @task = notification.notifiable if notification.notifiable.is_a?(Task)

    # Render dates in the recipient's own zone (jobs run outside any request).
    Time.use_zone(@user.time_zone) do
      mail to: email_address_with_name(@user.email_address, @user.name),
           subject: notification.title
    end
  end
end
