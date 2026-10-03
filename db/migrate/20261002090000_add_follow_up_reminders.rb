class AddFollowUpReminders < ActiveRecord::Migration[8.1]
  def change
    # Days without news after sending before a follow-up task is suggested (0 = off).
    add_column :users, :follow_up_after_days, :integer, null: false, default: 7
    # When the automatic follow-up was created, so it is never repeated.
    add_column :job_applications, :follow_up_suggested_at, :datetime
  end
end
