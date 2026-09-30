require "test_helper"

class JobApplicationEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @application = create_job_application(@user, title: "Programador Rails")
    @event = @application.job_application_events.create!(event_type: "saved", occurred_at: 2.days.ago)
  end

  test "create adds a note to the history without changing the status" do
    assert_difference -> { @application.job_application_events.count } => 1 do
      post job_application_job_application_events_url(@application),
           params: { job_application_event: { event_type: "follow_up", occurred_at: "2026-09-28T11:00",
                                              notes: "Enviei email ao recrutador" } }
    end
    assert_redirected_to job_application_url(@application, anchor: "historico")
    event = @application.job_application_events.last
    assert_equal "follow_up", event.event_type
    assert_equal Time.zone.local(2026, 9, 28, 11, 0), event.occurred_at
    assert @application.reload.saved?
    assert AuditLog.exists?(action: "job_application.event_added", resource_id: @application.id)
  end

  test "create without a date re-renders the application page" do
    assert_no_difference -> { JobApplicationEvent.count } do
      post job_application_job_application_events_url(@application),
           params: { job_application_event: { event_type: "note", occurred_at: "", notes: "Sem data" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_select "h1", "Programador Rails"
    assert_select ".timeline .timeline__item", 1
  end

  test "create with an absurd date is rejected" do
    assert_no_difference -> { JobApplicationEvent.count } do
      post job_application_job_application_events_url(@application),
           params: { job_application_event: { event_type: "note", occurred_at: "1970-01-01T10:00" } }
    end
    assert_response :unprocessable_entity
  end

  test "create with an unknown type is rejected" do
    assert_no_difference -> { JobApplicationEvent.count } do
      post job_application_job_application_events_url(@application),
           params: { job_application_event: { event_type: "hired", occurred_at: "2026-09-28T11:00" } }
    end
    assert_response :unprocessable_entity
  end

  test "destroy removes the event" do
    assert_difference -> { JobApplicationEvent.count } => -1 do
      delete job_application_job_application_event_url(@application, @event)
    end
    assert_redirected_to job_application_url(@application, anchor: "historico")
    assert AuditLog.exists?(action: "job_application.event_deleted", resource_id: @application.id)
  end

  test "cannot delete an event through a different application" do
    other = create_job_application(@user)
    assert_no_difference -> { JobApplicationEvent.count } do
      delete job_application_job_application_event_url(other, @event)
    end
    assert_response :not_found
  end

  test "another user cannot add or delete events" do
    sign_out
    sign_in_as(users(:two))

    assert_no_difference -> { JobApplicationEvent.count } do
      post job_application_job_application_events_url(@application),
           params: { job_application_event: { event_type: "note", occurred_at: "2026-09-28T11:00" } }
    end
    assert_response :not_found

    assert_no_difference -> { JobApplicationEvent.count } do
      delete job_application_job_application_event_url(@application, @event)
    end
    assert_response :not_found
  end
end
