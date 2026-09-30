module Calendar
  # Puts a connection in the "error" state after Google refused our credentials
  # and tells the user (once) that they need to reconnect.
  class AuthFailure
    MESSAGE = "Autorização expirada — volta a ligar a conta Google".freeze
    NOTIFICATION_TITLE = "Google Calendar desligado".freeze

    def self.call(connection)
      new(connection).call
    end

    def initialize(connection)
      @connection = connection
    end

    def call
      was_active = @connection.active?
      @connection.mark_error!(MESSAGE)
      return unless was_active

      notify
      AuditLog.record("calendar.authorization_failed", resource: @connection, user: @connection.user)
    end

    private
      def notify
        user = @connection.user
        return if user.notifications.unread.exists?(notification_type: "calendar", title: NOTIFICATION_TITLE)

        user.notifications.create!(
          notification_type: "calendar",
          title: NOTIFICATION_TITLE,
          body: "#{MESSAGE}. As tarefas continuam disponíveis na app; a sincronização fica parada até voltares a ligar a conta."
        )
      end
  end
end
