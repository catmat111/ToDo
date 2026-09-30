# Google Calendar integration (plan §12). Isolated module: task management never
# depends on it, and every entry point tolerates the integration being down.
module Calendar
  # Builds the API client used by services, jobs and controllers. Tests swap it
  # for a fake (see test/support/fake_google_calendar_client.rb).
  mattr_accessor :client_builder, default: -> { GoogleCalendarClient.new }

  def self.client
    client_builder.call
  end

  # Raised when Google rejects our credentials for good. Jobs discard it instead
  # of retrying, so an expired token never causes an endless sync loop.
  class AuthorizationError < StandardError; end
end
