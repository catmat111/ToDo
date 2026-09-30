require "test_helper"

class JobApplicationEventTest < ActiveSupport::TestCase
  setup do
    @application = create_job_application
  end

  test "valid with a known type and a date" do
    event = @application.job_application_events.new(event_type: "note", occurred_at: Time.current, notes: "Liguei")
    assert event.valid?
    assert_equal "Nota", event.label
  end

  test "requires occurred_at" do
    event = @application.job_application_events.new(event_type: "note", occurred_at: nil)
    assert_not event.valid?
    assert event.errors.of_kind?(:occurred_at, :blank)
  end

  test "rejects absurd dates" do
    too_old = @application.job_application_events.new(event_type: "note", occurred_at: Time.zone.local(1980, 1, 1))
    too_far = @application.job_application_events.new(event_type: "note", occurred_at: 10.years.from_now)
    assert_not too_old.valid?
    assert_not too_far.valid?
    assert_includes too_old.errors[:occurred_at], "não é uma data válida para o histórico"
  end

  test "rejects unknown event types" do
    event = @application.job_application_events.new(event_type: "hired", occurred_at: Time.current)
    assert_not event.valid?
    assert event.errors.key?(:event_type)
  end

  test "labels and status events" do
    assert_equal "Follow-up", JobApplicationEvent.label_for("follow_up")
    assert_equal "Candidatura enviada", JobApplicationEvent.label_for("applied")
    assert @application.job_application_events.new(event_type: "offer").status_event?
    assert_not @application.job_application_events.new(event_type: "note").status_event?
  end

  test "history is chronological and newest_first reverses it" do
    late = @application.job_application_events.create!(event_type: "note", occurred_at: 1.day.ago)
    early = @application.job_application_events.create!(event_type: "saved", occurred_at: 3.days.ago)

    assert_equal [ early, late ], @application.job_application_events.reload.to_a
    assert_equal [ late, early ], @application.job_application_events.newest_first.to_a
  end

  test "adding an event touches the application" do
    @application.update_columns(updated_at: 2.days.ago)
    @application.job_application_events.create!(event_type: "note", occurred_at: Time.current)
    assert_in_delta Time.current, @application.reload.updated_at, 5.seconds
  end
end
