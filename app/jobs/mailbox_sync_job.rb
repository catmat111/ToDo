# Reads new job replies from Gmail. With a connection id syncs that one; without
# arguments (hourly, config/recurring.yml) syncs every active connection.
class MailboxSyncJob < ApplicationJob
  queue_as :default
  retry_on GoogleCalendarClient::NetworkError, attempts: 3, wait: :polynomially_longer
  discard_on ActiveRecord::RecordNotFound

  def perform(connection_id = nil)
    connections = connection_id ? MailboxConnection.where(id: connection_id) : MailboxConnection.active
    connections.find_each { |connection| Inbox::Sync.call(connection) }
  end
end
