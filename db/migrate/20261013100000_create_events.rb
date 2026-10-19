# Calendar events: things that happen at a time (a meeting, a dinner) and aren't tasks to do.
class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.boolean :all_day, null: false, default: false
      t.string :location
      t.text :notes
      t.timestamps
    end
    add_index :events, [ :user_id, :starts_at ]
  end
end
