require "test_helper"

module JobApplications
  class TransitionTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      Current.session = @user.sessions.create!
      @application = create_job_application(@user, title: "Dev Rails")
    end

    teardown { Current.reset }

    test "allowed transition updates status and creates the matching event" do
      result = nil
      assert_difference -> { @application.job_application_events.count } => 1 do
        result = Transition.call(@application, to: "applied", notes: "Enviado pelo site")
      end

      assert result.success?
      assert @application.reload.applied?
      event = result.event
      assert_equal "applied", event.event_type
      assert_equal "Enviado pelo site", event.notes
      assert_empty result.tasks
    end

    test "every transition along the happy path records an event" do
      %w[applied interview interview offer withdrawn].each do |to|
        assert Transition.call(@application, to: to).success?, "#{to} should be allowed"
      end
      assert_equal %w[applied interview interview offer withdrawn],
                   @application.job_application_events.reload.map(&:event_type)
    end

    test "sets applied_at from occurred_at" do
      sent = 2.days.ago.change(usec: 0)
      Transition.call(@application, to: "applied", occurred_at: sent)
      assert_equal sent, @application.reload.applied_at
      assert_equal sent, @application.job_application_events.last.occurred_at
    end

    test "accepts occurred_at as a string in the user's zone" do
      Transition.call(@application, to: "applied", occurred_at: "2026-09-01T10:30")
      assert_equal Time.zone.local(2026, 9, 1, 10, 30), @application.reload.applied_at
    end

    test "rejects saved -> offer without changing anything" do
      result = nil
      assert_no_difference -> { JobApplicationEvent.count } do
        result = Transition.call(@application, to: "offer")
      end
      assert result.failure?
      assert_match "Não é possível passar de «Guardada» para «Oferta»", result.error
      assert @application.reload.saved?
    end

    test "rejected is terminal" do
      Transition.call(@application, to: "applied")
      assert Transition.call(@application, to: "rejected").success?

      result = Transition.call(@application, to: "interview")
      assert result.failure?
      assert_match "encerrada", result.error
      assert @application.reload.rejected?
    end

    test "rejects unknown statuses" do
      result = Transition.call(@application, to: "hired")
      assert result.failure?
      assert_match "Estado desconhecido", result.error
    end

    test "audits the change with from and to" do
      Transition.call(@application, to: "applied")
      log = AuditLog.where(action: "job_application.status_changed").last
      assert_equal "saved", log.metadata["from"]
      assert_equal "applied", log.metadata["to"]
      assert_equal @application.id, log.resource_id
      assert_equal @user, log.user
    end

    test "creates a follow-up task due in 7 days when applying" do
      result = nil
      assert_difference -> { @user.tasks.count } => 1 do
        result = Transition.call(@application, to: "applied", create_follow_up: "1")
      end

      task = result.tasks.first
      assert_equal "Follow-up: Dev Rails", task.title
      assert task.type_job?
      assert_equal @application, task.job_application
      assert_in_delta 7.days.from_now, task.due_at, 1.minute
    end

    test "does not create a follow-up when not asked" do
      assert_no_difference -> { Task.count } do
        Transition.call(@application, to: "applied", create_follow_up: "0")
      end
    end

    test "interview with a date creates a task and a reminder the day before" do
      Transition.call(@application, to: "applied")
      interview_at = 3.days.from_now.change(sec: 0)

      result = Transition.call(@application, to: "interview", interview_at: interview_at, notes: "Com a equipa")
      task = result.tasks.first
      assert_equal "Entrevista: Dev Rails", task.title
      assert_equal interview_at, task.starts_at
      assert_equal interview_at + 1.hour, task.due_at
      assert_equal [ interview_at - 1.day ], task.reminders.map(&:remind_at)
      assert_match "Entrevista marcada para", result.event.notes
      assert_match "Com a equipa", result.event.notes
    end

    test "interview less than a day away skips the reminder" do
      Transition.call(@application, to: "applied")
      result = Transition.call(@application, to: "interview", interview_at: 3.hours.from_now)
      assert_equal 1, result.tasks.size
      assert_empty result.tasks.first.reminders
    end

    test "interview without a date creates no task" do
      Transition.call(@application, to: "applied")
      assert_no_difference -> { Task.count } do
        assert Transition.call(@application, to: "interview", interview_at: "").success?
      end
    end

    test "rolls everything back when the event is invalid" do
      result = nil
      assert_no_difference -> { JobApplicationEvent.count } do
        result = Transition.call(@application, to: "applied", occurred_at: Time.zone.local(1980, 1, 1),
                                               create_follow_up: true)
      end
      assert result.failure?
      assert_match "não é uma data válida", result.error
      assert @application.reload.saved?
      assert_nil @application.applied_at
      assert_equal 0, Task.count
      assert @application.saved?, "in-memory status is restored too"
    end
  end
end
