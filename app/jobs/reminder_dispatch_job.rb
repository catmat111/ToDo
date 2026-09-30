# Runs every minute (config/recurring.yml) and delivers the reminders that are due.
class ReminderDispatchJob < ApplicationJob
  queue_as :default

  def perform
    Reminders::Dispatcher.call(now: Time.current)
  end
end
