require "test_helper"
require_relative "../../support/fake_google_calendar_client"

class Calendar::TaskSyncTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include CalendarTestHelpers

  setup do
    @fake = install_fake_google_client
    @connection = create_connection
    @task = create_task(users(:one), sync_to_calendar: true, due_at: 2.days.from_now.change(hour: 15, min: 0))
  end

  teardown { restore_google_client }

  def sync(task = @task, **options)
    Calendar::TaskSync.new(@connection, task.reload, client: @fake, access_token: "token", **options).call
  end

  test "creates the external event and stores its id and etag" do
    assert_equal :created, sync

    event = @connection.calendar_events.find_by!(task: @task)
    assert event.sync_synced?
    assert_equal @fake.events.keys.first, event.external_event_id
    assert_equal @fake.events.values.first["etag"], event.etag
    assert_not_nil event.last_synced_at
    assert_equal @task.title, @fake.events.values.first["summary"]
  end

  test "sincronizar duas vezes não cria dois eventos externos" do
    sync
    assert_equal :unchanged, sync

    assert_equal 1, @fake.events.size
    assert_equal 1, @fake.calls_to(:insert_event).size
    assert_equal 1, CalendarEvent.where(task: @task).count
  end

  test "an edited task updates the event it already has, using the stored id and etag" do
    sync
    event = @connection.calendar_events.find_by!(task: @task)
    @task.update!(title: "Entregar relatório")

    assert_equal :updated, sync

    update = @fake.calls_to(:update_event).last
    assert_equal event.external_event_id, update.args[:event_id]
    assert_equal event.etag, update.args[:etag]
    assert_equal 1, @fake.events.size
    assert_equal "Entregar relatório", @fake.events[event.external_event_id]["summary"]
    assert_not_equal event.etag, event.reload.etag
  end

  test "an event deleted in Google (404) is created again and the id replaced" do
    sync
    old_id = @connection.calendar_events.find_by!(task: @task).external_event_id
    @fake.delete_remotely(old_id)
    @task.update!(title: "Outro título")

    assert_equal :created, sync

    new_id = @connection.calendar_events.find_by!(task: @task).external_event_id
    assert_not_equal old_id, new_id
    assert @fake.events.key?(new_id)
    assert_equal 1, CalendarEvent.where(task: @task).count
  end

  test "a missing event is recreated even when the task did not change" do
    sync
    @fake.delete_remotely(@connection.calendar_events.find_by!(task: @task).external_event_id)

    assert_equal :created, sync
    assert_equal 1, @fake.events.size
  end

  test "remote time changes are imported when the task did not change" do
    sync
    event = @connection.calendar_events.find_by!(task: @task)
    new_start = 3.days.from_now.change(hour: 9, min: 0)
    new_end = new_start + 1.hour
    @fake.change_remotely(event.external_event_id, start: new_start, finish: new_end)

    assert_no_enqueued_jobs(only: CalendarTaskSyncJob) do
      assert_equal :imported, sync
    end

    assert_equal new_end.to_i, @task.reload.due_at.to_i
    assert_nil @task.starts_at, "only the fields the task uses are imported"
    assert event.reload.sync_synced?
    assert_equal @fake.events[event.external_event_id]["etag"], event.etag
    assert_equal 0, @fake.calls_to(:update_event).size
  end

  test "imports both start and end for tasks with a start date" do
    @task.update!(starts_at: @task.due_at - 2.hours)
    sync
    event = @connection.calendar_events.find_by!(task: @task)
    new_start = 4.days.from_now.change(hour: 10, min: 0)
    @fake.change_remotely(event.external_event_id, start: new_start, finish: new_start + 90.minutes)

    sync

    @task.reload
    assert_equal new_start.to_i, @task.starts_at.to_i
    assert_equal (new_start + 90.minutes).to_i, @task.due_at.to_i
  end

  test "when both sides changed nothing is overwritten and the user is notified once" do
    sync
    event = @connection.calendar_events.find_by!(task: @task)
    remote_start = 5.days.from_now.change(hour: 8, min: 0)
    @fake.change_remotely(event.external_event_id, start: remote_start, finish: remote_start + 1.hour)
    @task.update!(due_at: 6.days.from_now.change(hour: 18, min: 0))
    local_due = @task.due_at

    assert_difference -> { users(:one).notifications.where(notification_type: "calendar").count }, 1 do
      assert_equal :conflict, sync
    end

    event.reload
    assert event.sync_error?
    assert event.conflict?
    assert_match(/Conflito/, event.last_error)
    assert_equal local_due.to_i, @task.reload.due_at.to_i
    assert_equal (remote_start + 1.hour).iso8601, Time.zone.parse(@fake.events[event.external_event_id]["end"]["dateTime"]).iso8601

    assert_no_difference -> { Notification.count } do
      assert_equal :conflict, sync
    end
  end

  test "a remote change that does not touch the times is not a conflict" do
    sync
    event = @connection.calendar_events.find_by!(task: @task)
    @fake.change_remotely(event.external_event_id, summary: "Mudado no Google")
    @task.update!(title: "Mudado no ToDo")

    assert_equal :updated, sync
    assert_equal "Mudado no ToDo", @fake.events[event.external_event_id]["summary"]
    assert event.reload.sync_synced?
  end

  test "resolve_conflicts keeps the ToDo version" do
    sync
    event = @connection.calendar_events.find_by!(task: @task)
    @fake.change_remotely(event.external_event_id, start: 5.days.from_now, finish: 5.days.from_now + 1.hour)
    @task.update!(due_at: 6.days.from_now.change(hour: 18, min: 0))
    sync

    assert_equal :updated, sync(resolve_conflicts: true)
    assert event.reload.sync_synced?
    remote_end = Time.zone.parse(@fake.events[event.external_event_id]["end"]["dateTime"])
    assert_equal @task.reload.due_at.to_i, remote_end.to_i
  end

  test "a task that stopped syncing has its event removed" do
    sync
    external_id = @connection.calendar_events.find_by!(task: @task).external_event_id
    @task.update!(sync_to_calendar: false)

    assert_equal :removed, sync
    assert_empty @fake.events
    assert_nil CalendarEvent.find_by(external_event_id: external_id)
    assert_equal external_id, @fake.calls_to(:delete_event).last.args[:event_id]
  end

  test "removing an event already gone in Google is fine" do
    sync
    @fake.delete_remotely(@connection.calendar_events.find_by!(task: @task).external_event_id)
    @task.update!(archived_at: Time.current)

    assert_equal :removed, sync
    assert_equal 0, CalendarEvent.where(task: @task).count
  end

  test "non-eligible task without event is skipped" do
    task = create_task(users(:one), sync_to_calendar: true)
    assert_equal :skipped, sync(task)
    assert_empty @fake.calls
  end

  test "API errors are recorded on the mapping and re-raised" do
    @fake.fail_next(:insert_event, GoogleCalendarClient::Error.new("Google respondeu 400 (invalid)", status: 400))

    assert_raises(GoogleCalendarClient::Error) { sync }

    event = @connection.calendar_events.find_by!(task: @task)
    assert event.sync_error?
    assert_equal "Google respondeu 400 (invalid)", event.last_error
    assert_nil event.external_event_id

    assert_equal :created, sync, "the next run retries the insert"
    assert event.reload.sync_synced?
  end

  test "authentication errors are not recorded as task errors" do
    @fake.fail_next(:insert_event, GoogleCalendarClient::AuthError.new("Google respondeu 401", status: 401))

    assert_raises(GoogleCalendarClient::AuthError) { sync }
    assert_nil CalendarEvent.find_by(task: @task)
  end
end
