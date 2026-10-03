require "test_helper"

class TaskDependencyTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @cv = create_task(@user, title: "Atualizar CV")
    @apply = create_task(@user, title: "Candidatar-me")
  end

  test "a blocked task cannot start or complete until its blocker is done" do
    @apply.task_dependencies.create!(blocker: @cv)

    result = Tasks::ChangeStatus.call(@apply.reload, to: "completed")
    assert_not result.success?
    assert_match "Atualizar CV", result.error

    assert Tasks::ChangeStatus.call(@cv, to: "completed").success?
    assert Tasks::ChangeStatus.call(@apply.reload, to: "completed").success?
  end

  test "completing the last blocker notifies that the task can go ahead" do
    @apply.task_dependencies.create!(blocker: @cv)
    assert_difference -> { @user.notifications.count } => 1 do
      Tasks::ChangeStatus.call(@cv, to: "completed")
    end
    assert_match "Candidatar-me", @user.notifications.last.title
  end

  test "no self, no other user's task, no cycles" do
    assert_not @cv.task_dependencies.build(blocker: @cv).valid?
    assert_not @cv.task_dependencies.build(blocker: create_task(users(:two))).valid?

    @apply.task_dependencies.create!(blocker: @cv)        # apply waits for cv
    cycle = @cv.task_dependencies.build(blocker: @apply)   # cv would wait for apply
    assert_not cycle.valid?
    assert_match "ciclo", cycle.errors.full_messages.to_sentence
  end
end
