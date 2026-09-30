require "test_helper"
require_relative "../../support/fake_google_calendar_client"

class Calendar::TokenRefresherTest < ActiveSupport::TestCase
  include CalendarTestHelpers

  setup do
    @fake = FakeGoogleCalendarClient.new
    @connection = create_connection(access_token: "current-token", refresh_token: "the-refresh-token")
  end

  test "returns the stored token while it is valid" do
    assert_equal "current-token", Calendar::TokenRefresher.call(@connection, client: @fake)
    assert_empty @fake.calls
  end

  test "refreshes an expired token and keeps the refresh token" do
    @connection.update!(expires_at: 10.seconds.from_now)

    token = Calendar::TokenRefresher.call(@connection, client: @fake)

    assert_equal "refreshed-access-token", token
    assert_equal "the-refresh-token", @fake.calls_to(:refresh).first.args[:refresh_token]
    @connection.reload
    assert_equal "refreshed-access-token", @connection.access_token
    assert_equal "the-refresh-token", @connection.refresh_token
    assert @connection.expires_at > 30.minutes.from_now
  end

  test "stores a rotated refresh token" do
    @connection.update!(expires_at: 1.minute.ago)
    @fake.refresh_tokens = GoogleCalendarClient::TokenSet.new(access_token: "a2", refresh_token: "r2", expires_at: 1.hour.from_now, scope: nil)

    Calendar::TokenRefresher.call(@connection, client: @fake)

    assert_equal "r2", @connection.reload.refresh_token
  end

  test "force refreshes even when the token looks valid" do
    Calendar::TokenRefresher.call(@connection, client: @fake, force: true)
    assert_equal 1, @fake.calls_to(:refresh).size
  end

  test "an auth failure marks the connection, notifies once and raises a non-retryable error" do
    @connection.update!(expires_at: 1.minute.ago)
    @fake.fail_next(:refresh, GoogleCalendarClient::AuthError.new("Google respondeu 400 (invalid_grant)"))

    assert_difference -> { Notification.where(user: users(:one), notification_type: "calendar").count }, 1 do
      error = assert_raises(Calendar::AuthorizationError) { Calendar::TokenRefresher.call(@connection, client: @fake) }
      assert_equal "Autorização expirada — volta a ligar a conta Google", error.message
    end

    assert @connection.reload.error?
    assert_equal "Autorização expirada — volta a ligar a conta Google", @connection.last_error
  end

  test "a missing refresh token is an auth failure" do
    @connection.update!(expires_at: 1.minute.ago, refresh_token: nil)

    assert_raises(Calendar::AuthorizationError) { Calendar::TokenRefresher.call(@connection, client: @fake) }
    assert @connection.reload.error?
  end

  test "network errors propagate untouched so the job can retry" do
    @connection.update!(expires_at: 1.minute.ago)
    @fake.fail_next(:refresh, GoogleCalendarClient::NetworkError.new("timeout"))

    assert_raises(GoogleCalendarClient::NetworkError) { Calendar::TokenRefresher.call(@connection, client: @fake) }
    assert @connection.reload.active?
  end
end
