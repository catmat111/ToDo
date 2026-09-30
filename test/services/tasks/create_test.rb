require "test_helper"

module Tasks
  class CreateTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
    end

    test "creates a task and records it in the audit log" do
      result = nil
      assert_difference -> { @user.tasks.count } => 1, -> { AuditLog.where(action: "task.created").count } => 1 do
        result = Create.call(user: @user, params: { title: "Estudar álgebra", task_type: "exam", priority: "2" })
      end
      assert result.success?
      assert result.task.type_exam?
      assert_equal 2, result.task.priority
    end

    test "keeps only the user's own tags" do
      mine = @user.tags.create!(name: "Faculdade")
      theirs = users(:two).tags.create!(name: "Privada")

      result = Create.call(user: @user, params: { title: "Relatório", tag_ids: [ "", mine.id.to_s, theirs.id.to_s, "abc" ] })

      assert result.success?
      assert_equal [ mine ], result.task.reload.tags.to_a
    end

    test "creates the initial reminder from reminder_at" do
      remind_at = 2.days.from_now.change(sec: 0)
      result = Create.call(user: @user, params: { title: "Pagar propinas", reminder_at: remind_at.iso8601 })

      assert result.success?
      assert_equal [ remind_at ], result.task.reminders.pluck(:remind_at)
    end

    test "fails without saving anything when the reminder is in the past" do
      assert_no_difference -> { Task.count } do
        result = Create.call(user: @user, params: { title: "Tarde demais", reminder_at: 1.day.ago.iso8601 })
        assert result.failure?
        assert result.task.errors[:reminder_at].any?
      end
    end

    test "rejects a parent task from another user" do
      foreign = create_task(users(:two))
      result = Create.call(user: @user, params: { title: "Intruso", parent_task_id: foreign.id })

      assert result.failure?
      assert result.task.new_record?
      assert result.task.errors[:parent_task].any?
    end

    test "new subtasks go to the end of the parent's list" do
      parent = create_task
      create_task(parent_task: parent, position: 4)
      result = Create.call(user: @user, params: { title: "Último passo", parent_task_id: parent.id })
      assert_equal 5, result.task.position
    end

    test "ignores attributes outside the whitelist" do
      result = Create.call(user: @user, params: { title: "Minha", user_id: users(:two).id, archived_at: Time.current })
      assert_equal @user, result.task.user
      assert_nil result.task.archived_at
    end
  end
end
