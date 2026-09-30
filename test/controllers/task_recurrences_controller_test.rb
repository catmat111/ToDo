require "test_helper"

class TaskRecurrencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @task = create_task(users(:one), title: "Ginásio", due_at: 1.day.from_now)
  end

  test "create sets a recurrence" do
    assert_difference -> { TaskRecurrence.count } => 1 do
      post task_recurrence_url(@task), params: { task_recurrence: { frequency: "weekly", interval: "2", ends_at: "" } }
    end
    assert_redirected_to task_url(@task)
    assert_equal [ "weekly", 2 ], [ @task.recurrence.frequency, @task.recurrence.interval ]
    assert AuditLog.exists?(action: "task.recurrence_set", resource_id: @task.id)

    follow_redirect!
    assert_select "#task-recurrence", /A cada 2 semanas/
  end

  test "create twice updates the existing rule instead of duplicating it" do
    TaskRecurrence.create!(task: @task, frequency: "daily", interval: 1)
    assert_no_difference -> { TaskRecurrence.count } do
      post task_recurrence_url(@task), params: { task_recurrence: { frequency: "monthly", interval: "1" } }
    end
    assert @task.reload.recurrence.monthly?
  end

  test "invalid rule re-renders the task page" do
    assert_no_difference -> { TaskRecurrence.count } do
      post task_recurrence_url(@task), params: { task_recurrence: { frequency: "weekly", interval: "0" } }
    end
    assert_response :unprocessable_entity
    assert_select "h1", "Ginásio"
    assert_select "#task-recurrence .form-errors"
  end

  test "update changes the rule, including ends_at" do
    TaskRecurrence.create!(task: @task, frequency: "daily", interval: 1)
    patch task_recurrence_url(@task), params: { task_recurrence: { frequency: "yearly", interval: "1", ends_at: "2030-01-01T00:00" } }
    assert_redirected_to task_url(@task)
    recurrence = @task.reload.recurrence
    assert recurrence.yearly?
    assert_equal Time.zone.local(2030, 1, 1), recurrence.ends_at
  end

  test "invalid update keeps the saved rule" do
    TaskRecurrence.create!(task: @task, frequency: "daily", interval: 3)
    patch task_recurrence_url(@task), params: { task_recurrence: { frequency: "daily", interval: "999" } }
    assert_response :unprocessable_entity
    assert_select "#task-recurrence", /A cada 3 dias/
    assert_equal 3, @task.reload.recurrence.interval
  end

  test "destroy removes the rule" do
    TaskRecurrence.create!(task: @task, frequency: "daily", interval: 1)
    assert_difference -> { TaskRecurrence.count } => -1 do
      delete task_recurrence_url(@task)
    end
    assert_redirected_to task_url(@task)
  end

  test "another user gets 404" do
    TaskRecurrence.create!(task: @task, frequency: "daily", interval: 1)
    sign_in_as users(:two)

    post task_recurrence_url(@task), params: { task_recurrence: { frequency: "weekly", interval: "1" } }
    assert_response :not_found
    patch task_recurrence_url(@task), params: { task_recurrence: { frequency: "weekly", interval: "1" } }
    assert_response :not_found
    assert_no_difference -> { TaskRecurrence.count } do
      delete task_recurrence_url(@task)
    end
    assert_response :not_found
    assert @task.reload.recurrence.daily?
  end
end
