require "test_helper"

module JobApplications
  class CreateTaskTest < ActiveSupport::TestCase
    setup do
      Current.session = users(:one).sessions.create!
    end

    teardown { Current.reset }

    test "creates a job task linked to the application named after the stage" do
      application = create_job_application(title: "Dev Rails")
      result = CreateTask.call(application)

      assert result.success?
      task = result.tasks.first
      assert task.persisted?
      assert_equal "Candidatar-me: Dev Rails", task.title
      assert task.type_job?
      assert_equal application, task.job_application
      assert_equal users(:one), task.user
      assert AuditLog.exists?(action: "job_application.task_created", resource_id: application.id)
    end

    test "interview stage suggests preparing the interview" do
      application = create_job_application(title: "Dev Rails", status: "interview")
      assert_equal "Preparar entrevista: Dev Rails", CreateTask.call(application).tasks.first.title
    end

    test "long titles are truncated to fit the task" do
      application = create_job_application(title: "a" * 200)
      task = CreateTask.call(application).tasks.first
      assert task.persisted?
      assert_equal 200, task.title.length
    end
  end
end
