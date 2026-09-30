class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :parent_task, foreign_key: { to_table: :tasks }
      t.references :job_application, foreign_key: { on_delete: :nullify }
      t.string :title, null: false
      t.text :description
      t.string :task_type, null: false, default: "other"
      t.string :status, null: false, default: "pending"
      t.integer :priority, null: false, default: 0
      t.datetime :starts_at
      t.datetime :due_at
      t.datetime :completed_at
      t.datetime :archived_at
      t.integer :position, null: false, default: 0
      t.boolean :sync_to_calendar, null: false, default: false

      t.timestamps
    end
    add_index :tasks, [ :user_id, :status ]
    add_index :tasks, [ :user_id, :due_at ]
    add_index :tasks, [ :user_id, :archived_at ]

    create_table :task_recurrences do |t|
      t.references :task, null: false, foreign_key: true, index: { unique: true }
      t.string :frequency, null: false
      t.integer :interval, null: false, default: 1
      t.datetime :ends_at

      t.timestamps
    end

    create_table :tags do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color

      t.timestamps
    end
    add_index :tags, [ :user_id, :name ], unique: true

    create_table :task_tags do |t|
      t.references :task, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end
    add_index :task_tags, [ :task_id, :tag_id ], unique: true

    create_table :reminders do |t|
      t.references :task, null: false, foreign_key: true
      t.datetime :remind_at, null: false
      t.string :channel, null: false, default: "in_app"
      t.datetime :sent_at
      t.integer :attempts, null: false, default: 0
      t.text :last_error

      t.timestamps
    end
    add_index :reminders, [ :task_id, :remind_at, :channel ], unique: true
    add_index :reminders, [ :sent_at, :remind_at ]

    create_table :links do |t|
      t.references :user, null: false, foreign_key: true
      t.references :linkable, polymorphic: true, null: false
      t.text :url, null: false
      t.string :label

      t.timestamps
    end
  end
end
