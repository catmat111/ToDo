require "test_helper"

module Tasks
  class DuplicateTest < ActiveSupport::TestCase
    test "copies the task as pending, with tags, links and the subtask tree" do
      user = users(:one)
      tag = user.tags.create!(name: "Estudo")
      task = create_task(title: "Estudar", due_at: 2.days.from_now, priority: 2, tag_ids: [ tag.id ])
      task.reminders.create!(remind_at: 1.day.from_now)
      user.links.create!(linkable: task, url: "https://example.com", label: "Guia")
      child = create_task(title: "Ler", parent_task: task)
      create_task(title: "Resumir", parent_task: child)
      ChangeStatus.call(task, to: "in_progress")

      copy = Duplicate.call(task).task

      assert_equal [ "Estudar (cópia)", "pending", 2, [ tag ] ], [ copy.title, copy.status, copy.priority, copy.tags.to_a ]
      assert_equal task.due_at.to_i, copy.due_at.to_i
      assert_equal [ "https://example.com" ], copy.links.pluck(:url)
      assert_equal [ "Ler" ], copy.subtasks.pluck(:title)
      assert_equal [ "Resumir" ], copy.subtasks.first.subtasks.pluck(:title)
      assert_empty copy.reminders
      assert_equal [ "Ler" ], task.reload.subtasks.pluck(:title) # the original is untouched
    end
  end
end
