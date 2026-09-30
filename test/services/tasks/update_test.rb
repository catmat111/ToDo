require "test_helper"

module Tasks
  class UpdateTest < ActiveSupport::TestCase
    test "updates attributes and audits the changed fields" do
      task = create_task(title: "Antes")
      result = Update.call(task, params: { title: "Depois", priority: "3" })

      assert result.success?
      assert_equal [ "Depois", 3 ], [ task.reload.title, task.priority ]
      log = AuditLog.where(action: "task.updated", resource_id: task.id).last
      assert_equal %w[priority title], log.metadata["fields"].sort
    end

    test "a blank tag list removes every tag, foreign tags are ignored" do
      tag = users(:one).tags.create!(name: "Casa")
      foreign = users(:two).tags.create!(name: "Outro")
      task = create_task(tags: [ tag ])

      assert Update.call(task, params: { tag_ids: [ "", foreign.id.to_s ] }).success?
      assert_empty task.reload.tags
    end

    test "status changes go through the transition rules" do
      task = create_task
      task.update!(status: "completed")

      result = Update.call(task, params: { title: "Novo título", status: "in_progress" })
      assert result.failure?
      assert task.errors[:status].any?
      assert_equal "completed", task.reload.status
      assert_not_equal "Novo título", task.title
    end

    test "completing through the form also schedules the next occurrence" do
      task = create_task(due_at: 1.day.from_now)
      TaskRecurrence.create!(task: task, frequency: "weekly", interval: 1)

      result = Update.call(task, params: { status: "completed" })
      assert result.success?
      assert result.next_task.persisted?
      assert task.reload.completed?
    end

    test "invalid attributes are reported without saving" do
      task = create_task(title: "Válida")
      result = Update.call(task, params: { title: "" })
      assert result.failure?
      assert_equal "Válida", task.reload.title
    end
  end
end
