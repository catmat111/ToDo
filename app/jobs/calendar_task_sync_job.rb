# Syncs (or removes) the Google event of one task after it changed.
# Does nothing when the owner has no active Google connection.
class CalendarTaskSyncJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  discard_on Calendar::AuthorizationError
  discard_on GoogleClient::Error do |job, error|
    job.logger.warn("[calendar] task sync discarded: #{error.class}")
  end
  retry_on GoogleClient::NetworkError, attempts: 3, wait: :polynomially_longer

  def perform(task_id)
    task = Task.find_by(id: task_id)
    return if task.nil?

    connection = task.user.google_calendar
    return unless connection&.active?

    Calendar::Sync.new(connection).sync_task(task)
  end
end
