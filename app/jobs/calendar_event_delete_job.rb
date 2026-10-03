# Removes an external Google event after its task was deleted. An event that is
# already gone in Google is ignored. If the connection is not active, the
# orphan CalendarEvent row is cleaned up by the next full sync after reconnecting.
class CalendarEventDeleteJob < ApplicationJob
  queue_as :default

  discard_on Calendar::AuthorizationError
  discard_on GoogleClient::Error do |job, error|
    job.logger.warn("[calendar] event delete discarded: #{error.class}")
  end
  retry_on GoogleClient::NetworkError, attempts: 3, wait: :polynomially_longer

  def perform(connection_id, external_event_id)
    connection = CalendarConnection.find_by(id: connection_id)
    return if connection.nil? || external_event_id.blank?

    Calendar::Sync.new(connection).delete_event(external_event_id)
  end
end
