require "test_helper"

class TaskTagTest < ActiveSupport::TestCase
  test "links a task and a tag of the same user" do
    tag = users(:one).tags.create!(name: "Estudo")
    task = create_task
    assert TaskTag.new(task: task, tag: tag).valid?
  end

  test "rejects a tag that belongs to another user" do
    foreign_tag = users(:two).tags.create!(name: "Alheia")
    task = create_task(users(:one))
    task_tag = TaskTag.new(task: task, tag: foreign_tag)

    assert_not task_tag.valid?
    assert_includes task_tag.errors.full_messages, "Etiqueta tem de pertencer ao mesmo utilizador"
  end

  test "assigning another user's tag through the task fails" do
    foreign_tag = users(:two).tags.create!(name: "Alheia")
    task = create_task(users(:one))

    assert_raises(ActiveRecord::RecordInvalid) { task.tags << foreign_tag }
    assert_empty task.reload.tags
  end

  test "the same tag cannot be added twice to a task" do
    tag = users(:one).tags.create!(name: "Duplicada")
    task = create_task
    TaskTag.create!(task: task, tag: tag)

    duplicate = TaskTag.new(task: task, tag: tag)
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:tag_id, :taken)
  end

  test "requires both task and tag" do
    task_tag = TaskTag.new
    assert_not task_tag.valid?
    assert task_tag.errors.of_kind?(:task, :blank)
    assert task_tag.errors.of_kind?(:tag, :blank)
  end
end
