class CreateMailbox < ActiveRecord::Migration[8.1]
  def change
    # Read-only link to ONE Gmail label (the folder where job replies are kept).
    create_table :mailbox_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :email_address
      t.text :access_token   # encrypted (Active Record Encryption)
      t.text :refresh_token  # encrypted
      t.datetime :expires_at
      t.string :label_id
      t.string :label_name
      t.string :status, null: false, default: "active"
      t.text :last_error
      t.datetime :last_synced_at

      t.timestamps
    end

    # One row per email read from that label, with what the app thinks it means.
    create_table :email_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.references :job_application, foreign_key: { on_delete: :nullify } # suggested / confirmed match
      t.string :external_id, null: false   # Gmail message id
      t.string :from_name
      t.string :from_email
      t.string :subject
      t.text :excerpt
      t.datetime :received_at
      t.string :outcome, null: false, default: "unknown" # rejected / interview / offer / received / unknown
      t.string :review_status, null: false, default: "pending" # pending / confirmed / ignored
      t.datetime :reviewed_at

      t.timestamps
    end
    add_index :email_messages, [ :user_id, :external_id ], unique: true
    add_index :email_messages, [ :user_id, :review_status ]
  end
end
