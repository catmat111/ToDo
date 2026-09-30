class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.string :avatar_url
      t.text :objective
      t.string :theme, null: false, default: "light"
      t.string :timezone, null: false, default: "Europe/Lisbon"

      t.timestamps
    end
    add_index :users, :email_address, unique: true
  end
end
