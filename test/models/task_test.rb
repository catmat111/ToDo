require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "requires a title" do
    task = users(:one).tasks.new(title: "  ")
    assert_not task.valid?
    assert task.errors.added?(:title, :blank)
  end

  test "defaults to a pending, low priority task of type other" do
    task = create_task
    assert task.pending?
    assert task.type_other?
    assert_equal 0, task.priority
    assert_nil task.completed_at
  end

  test "rejects a due date before the start" do
    task = users(:one).tasks.new(title: "Exame", starts_at: 2.days.from_now, due_at: 1.day.from_now)
    assert_not task.valid?
    assert_includes task.errors[:due_at], "não pode ser anterior ao início"
  end

  test "uma subtarefa não pode pertencer a uma tarefa de outro utilizador" do
    foreign_parent = create_task(users(:two))
    subtask = users(:one).tasks.new(title: "Passo", parent_task: foreign_parent)
    assert_not subtask.valid?
    assert_includes subtask.errors[:parent_task], "tem de pertencer ao mesmo utilizador"
  end

  test "rejects a job application from another user" do
    application = create_job_application(users(:two))
    task = users(:one).tasks.new(title: "Entrevista", job_application: application)
    assert_not task.valid?
    assert task.errors[:job_application].any?
  end

  test "detects a cycle A -> B -> A" do
    a = create_task
    b = create_task(parent_task: a)
    a.parent_task = b
    assert_not a.valid?
    assert_includes a.errors[:parent_task], "criaria um ciclo na hierarquia"
  end

  test "a task cannot be its own parent" do
    a = create_task
    a.parent_task_id = a.id
    assert_not a.valid?
    assert_includes a.errors[:parent_task], "não pode ser a própria tarefa"
  end

  test "limits the hierarchy depth" do
    node = create_task
    (Task::MAX_DEPTH - 1).times { node = create_task(parent_task: node) }
    too_deep = users(:one).tasks.new(title: "Fundo", parent_task: node)
    assert_not too_deep.valid?
    assert too_deep.errors[:parent_task].any?
  end

  test "concluir uma tarefa atualiza completed_at" do
    task = create_task
    freeze_time do
      task.update!(status: "completed")
      assert_equal Time.current, task.completed_at
    end
  end

  test "reopening clears completed_at" do
    task = create_task
    task.update!(status: "completed")
    task.update!(status: "pending")
    assert_nil task.reload.completed_at
  end

  test "completed_at is set when a task is created already completed" do
    task = create_task(status: "completed")
    assert_not_nil task.completed_at
  end

  test "completed_at can't be forced on an open task" do
    task = create_task(completed_at: 1.day.ago)
    assert_nil task.reload.completed_at
  end

  test "allows the planned transitions" do
    expected = {
      "pending" => %w[in_progress completed cancelled],
      "in_progress" => %w[completed cancelled pending],
      "completed" => %w[pending],
      "cancelled" => %w[pending]
    }
    assert_equal expected, Task::TRANSITIONS
    assert create_task.can_transition_to?("in_progress")
    assert_not create_task(status: "completed").can_transition_to?("in_progress")
  end

  test "rejects invalid transitions on update" do
    task = create_task
    task.update!(status: "completed")
    assert_not task.update(status: "cancelled")
    assert_match "não pode passar de «Concluída» para «Cancelada»", task.errors[:status].first

    cancelled = create_task
    cancelled.update!(status: "cancelled")
    assert_not cancelled.update(status: "in_progress")
  end

  test "reminder_at must be in the future on create" do
    task = users(:one).tasks.new(title: "Lembrar", reminder_at: 1.hour.ago)
    assert_not task.valid?
    assert task.errors[:reminder_at].any?
    task.reminder_at = 1.hour.from_now
    assert task.valid?
  end

  test "labels in European Portuguese" do
    assert_equal %w[Projeto Rotina Exame Entrega Emprego Outro], Task::TYPES.map { |t| Task.type_label(t) }
    assert_equal "Em curso", Task.status_label("in_progress")
    assert_equal "Urgente", Task.priority_label(3)
  end

  test "progress ignores cancelled subtasks and suggests completing the parent" do
    parent = create_task
    done = create_task(parent_task: parent)
    create_task(parent_task: parent, status: "cancelled")
    done.update!(status: "completed")

    parent.reload
    assert_equal [ 1, 1 ], parent.progress
    assert parent.all_subtasks_completed?
    assert parent.suggest_completion?
    assert parent.pending?, "the parent is never auto-completed"
  end

  test "descendant_ids lists every level below the task" do
    root = create_task
    child = create_task(parent_task: root)
    grandchild = create_task(parent_task: child)
    create_task
    assert_equal [ child.id, grandchild.id ].sort, root.descendant_ids.sort
    assert_equal [], grandchild.descendant_ids
  end

  test "ancestors go from the direct parent up to the root" do
    root = create_task
    child = create_task(parent_task: root)
    grandchild = create_task(parent_task: child)
    assert_equal [ child, root ], grandchild.ancestors
  end

  test "overdue only for open tasks with a past due date" do
    assert create_task(due_at: 1.hour.ago).overdue?
    assert_not create_task(due_at: 1.hour.from_now).overdue?
    assert_not create_task(due_at: 1.hour.ago, status: "completed").overdue?
  end
end
