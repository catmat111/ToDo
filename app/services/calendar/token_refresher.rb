module Calendar
  # Returns a usable access token for a connection, refreshing it when it is
  # expired (or when +force+ is set after Google rejected the stored one).
  #
  # When Google refuses the refresh (revoked grant, invalid_grant…) the
  # connection is marked as error, the user is notified once and
  # Calendar::AuthorizationError is raised: callers must not retry.
  class TokenRefresher
    def self.call(connection, client:, force: false)
      new(connection, client: client).call(force: force)
    end

    def initialize(connection, client:)
      @connection = connection
      @client = client
    end

    def call(force: false)
      return @connection.access_token if !force && @connection.access_token.present? && !@connection.token_expired?

      tokens = @client.refresh(refresh_token: @connection.refresh_token)
      attributes = { access_token: tokens.access_token, expires_at: tokens.expires_at }
      attributes[:refresh_token] = tokens.refresh_token if tokens.refresh_token.present?
      attributes[:scope] = tokens.scope if tokens.scope.present?
      @connection.update!(attributes)
      @connection.access_token
    rescue GoogleCalendarClient::AuthError
      AuthFailure.call(@connection)
      raise AuthorizationError, AuthFailure::MESSAGE
    end
  end
end
