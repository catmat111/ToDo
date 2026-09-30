require "test_helper"
require_relative "../../support/fake_google_calendar_client"

class Calendar::SyncTest < ActiveSupport::TestCase
  include CalendarTestHelpers

  setup do
    @fake = install_fake_google_client
    @connection = create_connection
  end

  teardown { restore_google_client }

  def run_sync(**options)
    Calendar::Sync.new(@connection.reload, client: @fake, **options).call
  end

  def eligible_task(**attrs)
    create_task(users(:one), sync_to_calendar: true, due_at: 1.day.from_now.change(min: 0), **attrs)
  end

  test "syncs every eligible task of the connection's user and stamps last_synced_at" do
    first = eligible_task
    second = eligible_task(starts_at: 2.days.from_now, due_at: 2.days.from_now + 1.hour)
    create_task(users(:one), sync_to_calendar: false, due_at: 1.day.from_now)
    create_task(users(:one), sync_to_calendar: true)
    create_task(users(:one), sync_to_calendar: true, due_at: 1.day.from_now, archived_at: Time.current)
    create_task(users(:two), sync_to_calendar: true, due_at: 1.day.from_now)

    result = run_sync

    assert_equal 2, result.created
    assert_equal 2, @fake.events.size
    assert_equal [ first.id, second.id ].sort, @connection.calendar_events.pluck(:task_id).sort
    assert_not_nil @connection.reload.last_synced_at
    assert_nil @connection.last_error
  end

  test "sincronizar duas vezes não cria dois eventos externos" do
    eligible_task
    eligible_task

    run_sync
    result = run_sync

    assert_equal 2, @fake.events.size
    assert_equal 2, @fake.calls_to(:insert_event).size
    assert_equal 2, @connection.calendar_events.count
    assert_equal 2, result.unchanged
  end

  test "does nothing for connections that are not active" do
    eligible_task
    @connection.update!(status: "error")

    assert_nil run_sync
    assert_empty @fake.calls
  end

  test "refreshes an expired token before syncing" do
    @connection.update!(expires_at: 1.minute.ago)
    eligible_task

    run_sync

    assert_equal 1, @fake.calls_to(:refresh).size
    assert_equal "refreshed-access-token", @connection.reload.access_token
    assert_equal "refreshed-access-token", @fake.calls_to(:insert_event).first.args[:access_token]
  end

  test "expired token and failed refresh mark the connection as error and notify once" do
    @connection.update!(expires_at: 1.minute.ago)
    eligible_task
    @fake.fail_next(:refresh, GoogleCalendarClient::AuthError.new("Google respondeu 400 (invalid_grant)", status: 400), times: 2)

    assert_difference -> { users(:one).notifications.where(notification_type: "calendar").count }, 1 do
      assert_raises(Calendar::AuthorizationError) { run_sync }
    end

    @connection.reload
    assert @connection.error?
    assert_equal Calendar::AuthFailure::MESSAGE, @connection.last_error
    assert_empty @fake.calls_to(:insert_event)
    assert AuditLog.exists?(action: "calendar.authorization_failed", resource_id: @connection.id)

    # The connection is now inactive: further syncs are no-ops (no loop, no new notification).
    assert_no_difference -> { Notification.count } do
      assert_nil run_sync
    end
    assert_equal 1, @fake.calls_to(:refresh).size
  end

  test "a rejected access token is refreshed once and the sync retried" do
    eligible_task
    @fake.fail_next(:insert_event, GoogleCalendarClient::AuthError.new("Google respondeu 401", status: 401))

    result = run_sync

    assert_equal 1, result.created
    assert_equal 1, @fake.calls_to(:refresh).size
    assert @connection.reload.active?
  end

  test "a second rejection after refreshing is final" do
    eligible_task
    @fake.fail_next(:insert_event, GoogleCalendarClient::AuthError.new("Google respondeu 401", status: 401), times: 2)

    assert_raises(Calendar::AuthorizationError) { run_sync }
    assert @connection.reload.error?
  end

  test "per-task errors do not abort the run" do
    failing = eligible_task
    ok = eligible_task(due_at: 3.days.from_now)
    @fake.fail_next(:insert_event, GoogleCalendarClient::Error.new("Google respondeu 400 (badRequest)", status: 400))

    result = run_sync

    assert_equal 1, result.failed
    assert_equal 1, result.created
    assert @connection.calendar_events.find_by!(task: ok).sync_synced?
    assert @connection.calendar_events.find_by!(task: failing).sync_error?
    assert_not_nil @connection.reload.last_synced_at
    assert_match(/não sincronizou/, @connection.last_error)
  end

  test "network errors abort the run so the job can retry it" do
    eligible_task
    @fake.fail_next(:insert_event, GoogleCalendarClient::NetworkError.new("Falha de rede"))

    assert_raises(GoogleCalendarClient::NetworkError) { run_sync }
    assert_nil @connection.reload.last_synced_at
  end

  test "removes the external events of tasks that are no longer eligible or were deleted" do
    archived = eligible_task
    unsynced = eligible_task
    deleted = eligible_task
    kept = eligible_task
    run_sync
    assert_equal 4, @fake.events.size

    archived.update!(archived_at: Time.current)
    unsynced.update!(sync_to_calendar: false)
    deleted_event_id = @connection.calendar_events.find_by!(task: deleted).external_event_id
    deleted.destroy!

    result = run_sync

    assert_equal 3, result.removed
    assert_equal [ kept.id ], @connection.calendar_events.pluck(:task_id)
    assert_equal 1, @fake.events.size
    assert_not @fake.events.key?(deleted_event_id)
  end

  test "sync_task syncs a single task" do
    task = eligible_task
    other = eligible_task

    Calendar::Sync.new(@connection, client: @fake).sync_task(task)

    assert_equal [ task.id ], @connection.calendar_events.pluck(:task_id)
    assert_nil @connection.calendar_events.find_by(task: other)
  end

  test "delete_event removes the remote event and the mapping, ignoring 404" do
    task = eligible_task
    run_sync
    external_id = @connection.calendar_events.first.external_event_id
    CalendarEvent.where(task: task).update_all(task_id: nil)

    assert Calendar::Sync.new(@connection, client: @fake).delete_event(external_id)
    assert_empty @fake.events
    assert_equal 0, @connection.calendar_events.count

    assert Calendar::Sync.new(@connection, client: @fake).delete_event(external_id), "404 is ignored"
  end
end
