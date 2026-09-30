require "test_helper"

module Tasks
  class CompleteTest < ActiveSupport::TestCase
    setup do
      @starts_at = Time.zone.local(2026, 10, 5, 9, 0)
      @due_at = Time.zone.local(2026, 10, 5, 10, 0)
    end

    test "completes the task and sets completed_at" do
      task = create_task
      result = Complete.call(task)

      assert result.success?
      assert task.reload.completed?
      assert_not_nil task.completed_at
      assert_nil result.next_task
      assert AuditLog.exists?(action: "task.completed", resource_id: task.id)
    end

    test "completing a parent keeps its subtasks untouched" do
      parent = create_task
      open_child = create_task(parent_task: parent)
      started_child = create_task(parent_task: parent, status: "in_progress")

      assert Complete.call(parent).success?

      assert parent.reload.completed?
      assert open_child.reload.pending?
      assert started_child.reload.in_progress?
    end

    test "cannot complete a cancelled task" do
      task = create_task(status: "cancelled")
      result = Complete.call(task)
      assert result.failure?
      assert task.reload.cancelled?
    end

    test "a recurring task creates exactly one next occurrence with shifted dates" do
      tag = users(:one).tags.create!(name: "Rotina")
      parent = create_task
      task = create_task(title: "Regar plantas", description: "Varanda", task_type: "routine", priority: 2,
                         sync_to_calendar: true, parent_task: parent, starts_at: @starts_at, due_at: @due_at, tags: [ tag ])
      recurrence = TaskRecurrence.create!(task: task, frequency: "weekly", interval: 2)

      result = nil
      assert_difference -> { Task.count } => 1 do
        result = Complete.call(task)
      end

      next_task = result.next_task
      assert next_task.persisted?
      assert next_task.pending?
      assert_equal [ "Regar plantas", "Varanda", "routine", 2, true, parent.id ],
                   [ next_task.title, next_task.description, next_task.task_type, next_task.priority,
                     next_task.sync_to_calendar, next_task.parent_task_id ]
      assert_equal [ tag ], next_task.tags.to_a
      assert_equal @starts_at + 2.weeks, next_task.starts_at
      assert_equal @due_at + 2.weeks, next_task.due_at

      assert_equal next_task.id, recurrence.reload.task_id, "the rule moves to the new occurrence"
      assert_nil task.reload.recurrence
      assert task.completed?
      assert AuditLog.exists?(action: "task.recurred", resource_id: next_task.id)
    end

    test "completing the new occurrence creates only the following one" do
      task = create_task(due_at: @due_at)
      TaskRecurrence.create!(task: task, frequency: "daily", interval: 1)

      second = Complete.call(task).next_task
      third = nil
      assert_difference -> { Task.count } => 1 do
        third = Complete.call(second).next_task
      end
      assert_equal @due_at + 2.days, third.due_at
    end

    test "the rule is dropped when the next date falls after ends_at" do
      task = create_task(due_at: @due_at)
      recurrence = TaskRecurrence.create!(task: task, frequency: "monthly", interval: 1, ends_at: @due_at + 10.days)

      result = nil
      assert_no_difference -> { Task.count } do
        result = Complete.call(task)
      end

      assert result.success?
      assert_nil result.next_task
      assert_not TaskRecurrence.exists?(recurrence.id)
      assert task.reload.completed?
    end

    test "a dateless recurring task repeats without dates" do
      task = create_task(title: "Rever notas")
      TaskRecurrence.create!(task: task, frequency: "daily", interval: 1)

      next_task = Complete.call(task).next_task
      assert_equal "Rever notas", next_task.title
      assert_nil next_task.due_at
      assert_equal next_task, TaskRecurrence.last.task
    end
  end
end
