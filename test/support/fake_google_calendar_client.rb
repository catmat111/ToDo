# In-memory stand-in for GoogleCalendarClient: no network, records every call
# and keeps "remote" events so tests can assert idempotency, 404s, conflicts…
#
#   fake = FakeGoogleCalendarClient.new
#   Calendar.client_builder = -> { fake }
#   fake.fail_next(:refresh, GoogleClient::AuthError.new("invalid_grant"))
#   fake.change_remotely(event_id, start: t1, end: t2)
class FakeGoogleCalendarClient
  Call = Struct.new(:name, :args)

  attr_reader :calls, :events
  attr_accessor :refresh_tokens, :exchange_tokens

  def initialize
    @calls = []
    @events = {}
    @failures = Hash.new { |hash, key| hash[key] = [] }
    @sequence = 0
    @refresh_tokens = GoogleClient::TokenSet.new(
      access_token: "refreshed-access-token", refresh_token: nil, expires_at: 1.hour.from_now, scope: GoogleCalendarClient::SCOPE
    )
    @exchange_tokens = GoogleClient::TokenSet.new(
      access_token: "fresh-access-token", refresh_token: "fresh-refresh-token", expires_at: 1.hour.from_now, scope: GoogleCalendarClient::SCOPE
    )
  end

  # Queue an error to be raised by the next call(s) to +method+.
  def fail_next(method, error, times: 1)
    times.times { @failures[method.to_sym] << error }
    self
  end

  def calls_to(name)
    calls.select { |call| call.name == name.to_sym }
  end

  # Simulates the user editing the event in Google Calendar (new etag).
  def change_remotely(event_id, start: nil, finish: nil, summary: nil)
    event = events.fetch(event_id)
    event["start"] = { "dateTime" => start.iso8601 } if start
    event["end"] = { "dateTime" => finish.iso8601 } if finish
    event["summary"] = summary if summary
    event["etag"] = next_etag
    event
  end

  def delete_remotely(event_id)
    events.delete(event_id)
  end

  # --- GoogleCalendarClient API ---------------------------------------------

  def authorization_url(state:, redirect_uri:)
    record(:authorization_url, state: state, redirect_uri: redirect_uri)
    query = URI.encode_www_form(state: state, redirect_uri: redirect_uri, scope: GoogleCalendarClient::SCOPE)
    "https://accounts.google.com/o/oauth2/v2/auth?#{query}"
  end

  def exchange_code(code:, redirect_uri:)
    record(:exchange_code, code: code, redirect_uri: redirect_uri)
    exchange_tokens
  end

  def refresh(refresh_token:)
    record(:refresh, refresh_token: refresh_token)
    raise GoogleClient::AuthError, "Sem refresh token disponível" if refresh_token.blank?
    refresh_tokens
  end

  def revoke(token:)
    record(:revoke, token: token)
    true
  end

  def insert_event(calendar_id:, access_token:, body:)
    record(:insert_event, calendar_id: calendar_id, access_token: access_token, body: body)
    id = "evt_#{@sequence += 1}"
    events[id] = body.deep_stringify_keys.merge("id" => id, "etag" => next_etag, "status" => "confirmed")
    events[id].deep_dup
  end

  def update_event(calendar_id:, access_token:, event_id:, body:, etag: nil)
    record(:update_event, calendar_id: calendar_id, access_token: access_token, event_id: event_id, body: body, etag: etag)
    existing = events[event_id] or raise GoogleClient::NotFoundError.new("Google respondeu 404", status: 404)
    if etag.present? && etag != existing["etag"]
      raise GoogleClient::ConflictError.new("Google respondeu 412", status: 412)
    end
    events[event_id] = body.deep_stringify_keys.merge("id" => event_id, "etag" => next_etag, "status" => "confirmed")
    events[event_id].deep_dup
  end

  def get_event(calendar_id:, access_token:, event_id:)
    record(:get_event, calendar_id: calendar_id, access_token: access_token, event_id: event_id)
    existing = events[event_id] or raise GoogleClient::NotFoundError.new("Google respondeu 404", status: 404)
    existing.deep_dup
  end

  def delete_event(calendar_id:, access_token:, event_id:)
    record(:delete_event, calendar_id: calendar_id, access_token: access_token, event_id: event_id)
    events.delete(event_id) or raise GoogleClient::NotFoundError.new("Google respondeu 404", status: 404)
    true
  end

  private
    def record(name, **args)
      calls << Call.new(name, args)
      error = @failures[name].shift
      raise error if error
    end

    def next_etag
      "\"etag-#{@sequence += 1}\""
    end
end

# Helpers shared by the calendar tests.
module CalendarTestHelpers
  def install_fake_google_client
    @fake_google = FakeGoogleCalendarClient.new
    fake = @fake_google
    @previous_client_builder = Calendar.client_builder
    Calendar.client_builder = -> { fake }
    fake
  end

  def restore_google_client
    Calendar.client_builder = @previous_client_builder if @previous_client_builder
  end

  def create_connection(user = users(:one), **attrs)
    user.calendar_connections.create!({
      provider: "google", access_token: "access-#{SecureRandom.hex(4)}", refresh_token: "refresh-#{SecureRandom.hex(4)}",
      expires_at: 1.hour.from_now, scope: GoogleCalendarClient::SCOPE, status: "active"
    }.merge(attrs))
  end

  def with_google_credentials(client_id: "test-client-id", client_secret: "test-client-secret")
    config = Rails.configuration.x.google
    previous = [ config.client_id, config.client_secret ]
    config.client_id = client_id
    config.client_secret = client_secret
    yield
  ensure
    config.client_id, config.client_secret = previous
  end
end
