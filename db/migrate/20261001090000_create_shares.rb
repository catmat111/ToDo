class CreateShares < ActiveRecord::Migration[8.1]
  def change
    create_table :shares do |t|
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      # What was shared (Task, JobListing or JobApplication of the sender).
      t.references :shareable, polymorphic: true
      # Snapshot, so the share still makes sense if the original is deleted.
      t.string :title, null: false
      t.text :message
      t.string :status, null: false, default: "pending"
      t.datetime :responded_at
      # The copy created in the recipient's account when accepted.
      t.references :copy, polymorphic: true

      t.timestamps
    end
    add_index :shares, [ :recipient_id, :status ]
  end
end
