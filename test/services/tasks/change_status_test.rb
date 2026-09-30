require "test_helper"

module Tasks
  class ChangeStatusTest < ActiveSupport::TestCase
    test "starts a pending task and audits it with from/to" do
      task = create_task
      result = ChangeStatus.call(task, to: "in_progress")

      assert result.success?
      assert task.reload.in_progress?
      log = AuditLog.where(action: "task.started", resource_id: task.id).last
      assert_equal({ "from" => "pending", "to" => "in_progress" }, log.metadata)
    end

    test "reopening a completed task is audited as reopened" do
      task = create_task
      ChangeStatus.call(task, to: "completed")
      result = ChangeStatus.call(task, to: "pending")

      assert result.success?
      assert_nil task.reload.completed_at
      assert AuditLog.exists?(action: "task.reopened", resource_id: task.id)
    end

    test "cancels a task" do
      task = create_task
      assert ChangeStatus.call(task, to: "cancelled").success?
      assert AuditLog.exists?(action: "task.cancelled", resource_id: task.id)
    end

    test "rejects transitions outside the plan" do
      task = create_task
      ChangeStatus.call(task, to: "completed")

      result = ChangeStatus.call(task, to: "in_progress")
      assert result.failure?
      assert_equal "Não é possível passar de «Concluída» para «Em curso».", result.error
      assert task.reload.completed?
    end

    test "rejects unknown statuses and no-op changes" do
      task = create_task
      assert ChangeStatus.call(task, to: "done").failure?
      assert ChangeStatus.call(task, to: "pending").failure?
      assert task.reload.pending?
    end
  end
end
