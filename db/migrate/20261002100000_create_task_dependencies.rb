class CreateTaskDependencies < ActiveRecord::Migration[8.1]
  def change
    # task_id waits for blocker_id ("bloqueada por").
    create_table :task_dependencies do |t|
      t.references :task, null: false, foreign_key: true
      t.references :blocker, null: false, foreign_key: { to_table: :tasks }

      t.timestamps
    end
    add_index :task_dependencies, [ :task_id, :blocker_id ], unique: true
  end
end
