# Runs daily at 9:00 (config/recurring.yml). See JobApplications::FollowUps.
class FollowUpReminderJob < ApplicationJob
  queue_as :default

  def perform
    JobApplications::FollowUps.call
  end
end
