class CreateJobDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :job_searches do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :source, null: false, default: "linkedin"
      t.string :query
      t.boolean :active, null: false, default: true
      t.datetime :last_run_at

      t.timestamps
    end

    create_table :job_filters do |t|
      t.references :job_search, null: false, foreign_key: true
      t.string :key, null: false
      t.string :value, null: false
      t.string :operator, null: false, default: "equals"

      t.timestamps
    end
    add_index :job_filters, [ :job_search_id, :key ]

    create_table :job_listings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :job_search, foreign_key: { on_delete: :nullify }
      t.string :external_id
      t.string :source, null: false, default: "other"
      t.string :title, null: false
      t.string :company_name
      t.string :location
      t.text :url, null: false
      t.text :normalized_url, null: false
      t.text :description
      t.datetime :published_at
      t.datetime :discovered_at, null: false

      t.timestamps
    end
    add_index :job_listings, [ :user_id, :normalized_url ], unique: true
    add_index :job_listings, [ :user_id, :source, :external_id ], unique: true
    add_index :job_listings, [ :source, :external_id ]

    create_table :job_applications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :job_listing, foreign_key: { on_delete: :nullify }
      # Snapshot so the application keeps its meaning if the listing disappears.
      t.string :title, null: false
      t.string :company_name
      t.string :status, null: false, default: "saved"
      t.datetime :applied_at
      t.text :notes

      t.timestamps
    end
    add_index :job_applications, [ :user_id, :status ]
    add_index :job_applications, [ :user_id, :job_listing_id ], unique: true

    create_table :job_application_events do |t|
      t.references :job_application, null: false, foreign_key: true
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.text :notes

      t.timestamps
    end
    add_index :job_application_events, [ :job_application_id, :occurred_at ]
  end
end
