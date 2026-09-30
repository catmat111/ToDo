module Calendar
  # Revokes the Google grant (best effort) and forgets the connection and its
  # event mappings. Events already created stay in the user's Google Calendar.
  class Disconnect
    def self.call(connection, client: Calendar.client)
      new(connection, client: client).call
    end

    def initialize(connection, client:)
      @connection = connection
      @client = client
    end

    def call
      revoked = revoke
      @connection.destroy!
      AuditLog.record("calendar.disconnected", resource: @connection, user: @connection.user, revoked: revoked)
      true
    end

    private
      def revoke
        token = @connection.refresh_token.presence || @connection.access_token
        return false if token.blank?

        @client.revoke(token: token)
        true
      rescue GoogleCalendarClient::Error => e
        Rails.logger.info("[calendar] revoke failed (ignored): #{e.class}")
        false
      end
  end
end
