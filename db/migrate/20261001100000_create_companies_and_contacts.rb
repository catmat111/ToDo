class CreateCompaniesAndContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :website
      t.string :location
      t.text :notes

      t.timestamps
    end
    add_index :companies, [ :user_id, :name ], unique: true

    create_table :contacts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :company, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.string :role
      t.string :email
      t.string :phone
      t.string :linkedin_url
      t.text :notes

      t.timestamps
    end

    add_reference :job_applications, :company, foreign_key: { on_delete: :nullify }
    add_reference :job_applications, :contact, foreign_key: { on_delete: :nullify }
  end
end
