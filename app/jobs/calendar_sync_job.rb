# Full sync of one Google connection (Calendar::Sync).
#
# Retries only transient network failures. Authentication problems are handled
# inside the sync (connection marked as error + notification) and the job is
# discarded: an expired token never causes an infinite sync loop.
class CalendarSyncJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  discard_on Calendar::AuthorizationError
  discard_on GoogleClient::Error do |job, error|
    job.logger.warn("[calendar] sync discarded: #{error.class}")
  end
  # Declared last so it wins over the generic GoogleClient::Error handler.
  retry_on GoogleClient::NetworkError, attempts: 3, wait: :polynomially_longer do |job, error|
    CalendarConnection.find_by(id: job.arguments.first)&.update(last_error: "Falha de rede ao contactar a Google. Tenta sincronizar mais tarde.")
    job.logger.warn("[calendar] sync gave up after retries: #{error.class}")
  end

  def perform(connection_id, resolve_conflicts: false)
    connection = CalendarConnection.find(connection_id)
    Calendar::Sync.new(connection, resolve_conflicts: resolve_conflicts).call
  end
end
