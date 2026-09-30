module Calendar
  # Stores (or refreshes) the user's Google connection after a successful OAuth
  # callback, then schedules the first full sync.
  class Connect
    def self.call(user:, tokens:)
      new(user: user, tokens: tokens).call
    end

    def initialize(user:, tokens:)
      @user = user
      @tokens = tokens
    end

    def call
      connection = @user.calendar_connections.find_or_initialize_by(provider: "google")
      reconnected = connection.persisted?

      connection.assign_attributes(
        access_token: @tokens.access_token,
        expires_at: @tokens.expires_at,
        scope: @tokens.scope.presence || GoogleCalendarClient::SCOPE,
        status: "active",
        last_error: nil
      )
      # Google only sends a refresh token on consent; keep the previous one otherwise.
      connection.refresh_token = @tokens.refresh_token if @tokens.refresh_token.present?
      connection.save!

      AuditLog.record("calendar.connected", resource: connection, user: @user, reconnected: reconnected)
      CalendarSyncJob.perform_later(connection.id)
      connection
    end
  end
end
