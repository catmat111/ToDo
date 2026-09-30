class CreateCalendarNotificationsAudit < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false, default: "google"
      t.string :external_account_id
      t.string :calendar_id, null: false, default: "primary"
      # Encrypted at rest with Active Record Encryption (see CalendarConnection).
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at
      t.string :scope
      t.string :status, null: false, default: "active"
      t.text :last_error
      t.datetime :last_synced_at

      t.timestamps
    end
    add_index :calendar_connections, [ :user_id, :provider ], unique: true

    create_table :calendar_events do |t|
      t.references :calendar_connection, null: false, foreign_key: true
      t.references :task, foreign_key: { on_delete: :nullify }
      t.string :external_event_id
      t.string :etag
      t.datetime :last_synced_at
      t.string :sync_status, null: false, default: "pending"
      t.text :last_error

      t.timestamps
    end
    add_index :calendar_events, [ :calendar_connection_id, :external_event_id ], unique: true
    add_index :calendar_events, [ :calendar_connection_id, :task_id ], unique: true

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :notifiable, polymorphic: true
      t.string :notification_type, null: false
      t.string :title, null: false
      t.text :body
      t.datetime :read_at

      t.timestamps
    end
    add_index :notifications, [ :user_id, :read_at ]

    create_table :audit_logs do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.string :resource_type
      t.bigint :resource_id
      t.json :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :audit_logs, [ :resource_type, :resource_id ]
    add_index :audit_logs, [ :user_id, :created_at ]
  end
end
