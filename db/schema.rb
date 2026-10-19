# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_13_100000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "audit_logs", force: :cascade do |t|
    t.integer "user_id"
    t.string "action", null: false
    t.string "resource_type"
    t.bigint "resource_id"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource_type_and_resource_id"
    t.index ["user_id", "created_at"], name: "index_audit_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "calendar_connections", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "provider", default: "google", null: false
    t.string "external_account_id"
    t.string "calendar_id", default: "primary", null: false
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "expires_at"
    t.string "scope"
    t.string "status", default: "active", null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "provider"], name: "index_calendar_connections_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_calendar_connections_on_user_id"
  end

  create_table "calendar_events", force: :cascade do |t|
    t.integer "calendar_connection_id", null: false
    t.integer "task_id"
    t.string "external_event_id"
    t.string "etag"
    t.datetime "last_synced_at"
    t.string "sync_status", default: "pending", null: false
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["calendar_connection_id", "external_event_id"], name: "idx_on_calendar_connection_id_external_event_id_fa47ff93a7", unique: true
    t.index ["calendar_connection_id", "task_id"], name: "index_calendar_events_on_calendar_connection_id_and_task_id", unique: true
    t.index ["calendar_connection_id"], name: "index_calendar_events_on_calendar_connection_id"
    t.index ["task_id"], name: "index_calendar_events_on_task_id"
  end

  create_table "companies", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "website"
    t.string "location"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_companies_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_companies_on_user_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "company_id"
    t.string "name", null: false
    t.string "role"
    t.string "email"
    t.string "phone"
    t.string "linkedin_url"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_contacts_on_company_id"
    t.index ["user_id"], name: "index_contacts_on_user_id"
  end

  create_table "email_messages", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "job_application_id"
    t.string "external_id", null: false
    t.string "from_name"
    t.string "from_email"
    t.string "subject"
    t.text "excerpt"
    t.datetime "received_at"
    t.string "outcome", default: "unknown", null: false
    t.string "review_status", default: "pending", null: false
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_application_id"], name: "index_email_messages_on_job_application_id"
    t.index ["user_id", "external_id"], name: "index_email_messages_on_user_id_and_external_id", unique: true
    t.index ["user_id", "review_status"], name: "index_email_messages_on_user_id_and_review_status"
    t.index ["user_id"], name: "index_email_messages_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at"
    t.boolean "all_day", default: false, null: false
    t.string "location"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "starts_at"], name: "index_events_on_user_id_and_starts_at"
    t.index ["user_id"], name: "index_events_on_user_id"
  end

  create_table "job_application_events", force: :cascade do |t|
    t.integer "job_application_id", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_application_id", "occurred_at"], name: "idx_on_job_application_id_occurred_at_1adce1b496"
    t.index ["job_application_id"], name: "index_job_application_events_on_job_application_id"
  end

  create_table "job_applications", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "job_listing_id"
    t.string "title", null: false
    t.string "company_name"
    t.string "status", default: "saved", null: false
    t.datetime "applied_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "company_id"
    t.integer "contact_id"
    t.string "work_mode"
    t.integer "salary_min"
    t.integer "salary_max"
    t.string "salary_period", default: "month", null: false
    t.datetime "follow_up_suggested_at"
    t.index ["company_id"], name: "index_job_applications_on_company_id"
    t.index ["contact_id"], name: "index_job_applications_on_contact_id"
    t.index ["job_listing_id"], name: "index_job_applications_on_job_listing_id"
    t.index ["user_id", "job_listing_id"], name: "index_job_applications_on_user_id_and_job_listing_id", unique: true
    t.index ["user_id", "status"], name: "index_job_applications_on_user_id_and_status"
    t.index ["user_id"], name: "index_job_applications_on_user_id"
    t.index ["work_mode"], name: "index_job_applications_on_work_mode"
  end

  create_table "job_filters", force: :cascade do |t|
    t.integer "job_search_id", null: false
    t.string "key", null: false
    t.string "value", null: false
    t.string "operator", default: "equals", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_search_id", "key"], name: "index_job_filters_on_job_search_id_and_key"
    t.index ["job_search_id"], name: "index_job_filters_on_job_search_id"
  end

  create_table "job_listings", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "job_search_id"
    t.string "external_id"
    t.string "source", default: "other", null: false
    t.string "title", null: false
    t.string "company_name"
    t.string "location"
    t.text "url", null: false
    t.text "normalized_url", null: false
    t.text "description"
    t.datetime "published_at"
    t.datetime "discovered_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "work_mode"
    t.integer "salary_min"
    t.integer "salary_max"
    t.string "salary_period", default: "month", null: false
    t.index ["job_search_id"], name: "index_job_listings_on_job_search_id"
    t.index ["source", "external_id"], name: "index_job_listings_on_source_and_external_id"
    t.index ["user_id", "normalized_url"], name: "index_job_listings_on_user_id_and_normalized_url", unique: true
    t.index ["user_id", "source", "external_id"], name: "index_job_listings_on_user_id_and_source_and_external_id", unique: true
    t.index ["user_id"], name: "index_job_listings_on_user_id"
    t.index ["work_mode"], name: "index_job_listings_on_work_mode"
  end

  create_table "job_searches", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "source", default: "linkedin", null: false
    t.string "query"
    t.boolean "active", default: true, null: false
    t.datetime "last_run_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_job_searches_on_user_id"
  end

  create_table "links", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "linkable_type", null: false
    t.integer "linkable_id", null: false
    t.text "url", null: false
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["linkable_type", "linkable_id"], name: "index_links_on_linkable"
    t.index ["user_id"], name: "index_links_on_user_id"
  end

  create_table "mailbox_connections", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "email_address"
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "expires_at"
    t.string "label_id"
    t.string "label_name"
    t.string "status", default: "active", null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_mailbox_connections_on_user_id", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "notifiable_type"
    t.integer "notifiable_id"
    t.string "notification_type", null: false
    t.string "title", null: false
    t.text "body"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "reminders", force: :cascade do |t|
    t.integer "task_id", null: false
    t.datetime "remind_at", null: false
    t.string "channel", default: "in_app", null: false
    t.datetime "sent_at"
    t.integer "attempts", default: 0, null: false
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sent_at", "remind_at"], name: "index_reminders_on_sent_at_and_remind_at"
    t.index ["task_id", "remind_at", "channel"], name: "index_reminders_on_task_id_and_remind_at_and_channel", unique: true
    t.index ["task_id"], name: "index_reminders_on_task_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shares", force: :cascade do |t|
    t.integer "sender_id", null: false
    t.integer "recipient_id", null: false
    t.string "shareable_type"
    t.integer "shareable_id"
    t.string "title", null: false
    t.text "message"
    t.string "status", default: "pending", null: false
    t.datetime "responded_at"
    t.string "copy_type"
    t.integer "copy_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["copy_type", "copy_id"], name: "index_shares_on_copy"
    t.index ["recipient_id", "status"], name: "index_shares_on_recipient_id_and_status"
    t.index ["recipient_id"], name: "index_shares_on_recipient_id"
    t.index ["sender_id"], name: "index_shares_on_sender_id"
    t.index ["shareable_type", "shareable_id"], name: "index_shares_on_shareable"
  end

  create_table "tags", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_tags_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "task_dependencies", force: :cascade do |t|
    t.integer "task_id", null: false
    t.integer "blocker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocker_id"], name: "index_task_dependencies_on_blocker_id"
    t.index ["task_id", "blocker_id"], name: "index_task_dependencies_on_task_id_and_blocker_id", unique: true
    t.index ["task_id"], name: "index_task_dependencies_on_task_id"
  end

  create_table "task_recurrences", force: :cascade do |t|
    t.integer "task_id", null: false
    t.string "frequency", null: false
    t.integer "interval", default: 1, null: false
    t.datetime "ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id"], name: "index_task_recurrences_on_task_id", unique: true
  end

  create_table "task_tags", force: :cascade do |t|
    t.integer "task_id", null: false
    t.integer "tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_task_tags_on_tag_id"
    t.index ["task_id", "tag_id"], name: "index_task_tags_on_task_id_and_tag_id", unique: true
    t.index ["task_id"], name: "index_task_tags_on_task_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "parent_task_id"
    t.integer "job_application_id"
    t.string "title", null: false
    t.text "description"
    t.string "task_type", default: "other", null: false
    t.string "status", default: "pending", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "starts_at"
    t.datetime "due_at"
    t.datetime "completed_at"
    t.datetime "archived_at"
    t.integer "position", default: 0, null: false
    t.boolean "sync_to_calendar", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_application_id"], name: "index_tasks_on_job_application_id"
    t.index ["parent_task_id"], name: "index_tasks_on_parent_task_id"
    t.index ["user_id", "archived_at"], name: "index_tasks_on_user_id_and_archived_at"
    t.index ["user_id", "due_at"], name: "index_tasks_on_user_id_and_due_at"
    t.index ["user_id", "status"], name: "index_tasks_on_user_id_and_status"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.string "avatar_url"
    t.text "objective"
    t.string "theme", default: "light", null: false
    t.string "timezone", default: "Europe/Lisbon", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "follow_up_after_days", default: 7, null: false
    t.boolean "linkedin_app"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_logs", "users", on_delete: :nullify
  add_foreign_key "calendar_connections", "users"
  add_foreign_key "calendar_events", "calendar_connections"
  add_foreign_key "calendar_events", "tasks", on_delete: :nullify
  add_foreign_key "companies", "users"
  add_foreign_key "contacts", "companies", on_delete: :nullify
  add_foreign_key "contacts", "users"
  add_foreign_key "email_messages", "job_applications", on_delete: :nullify
  add_foreign_key "email_messages", "users"
  add_foreign_key "events", "users"
  add_foreign_key "job_application_events", "job_applications"
  add_foreign_key "job_applications", "companies", on_delete: :nullify
  add_foreign_key "job_applications", "contacts", on_delete: :nullify
  add_foreign_key "job_applications", "job_listings", on_delete: :nullify
  add_foreign_key "job_applications", "users"
  add_foreign_key "job_filters", "job_searches"
  add_foreign_key "job_listings", "job_searches", on_delete: :nullify
  add_foreign_key "job_listings", "users"
  add_foreign_key "job_searches", "users"
  add_foreign_key "links", "users"
  add_foreign_key "mailbox_connections", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "reminders", "tasks"
  add_foreign_key "sessions", "users"
  add_foreign_key "shares", "users", column: "recipient_id"
  add_foreign_key "shares", "users", column: "sender_id"
  add_foreign_key "tags", "users"
  add_foreign_key "task_dependencies", "tasks"
  add_foreign_key "task_dependencies", "tasks", column: "blocker_id"
  add_foreign_key "task_recurrences", "tasks"
  add_foreign_key "task_tags", "tags"
  add_foreign_key "task_tags", "tasks"
  add_foreign_key "tasks", "job_applications", on_delete: :nullify
  add_foreign_key "tasks", "tasks", column: "parent_task_id"
  add_foreign_key "tasks", "users"
end
