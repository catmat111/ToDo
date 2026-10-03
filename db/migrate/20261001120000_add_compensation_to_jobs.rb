class AddCompensationToJobs < ActiveRecord::Migration[8.1]
  def change
    %i[job_listings job_applications].each do |table|
      add_column table, :work_mode, :string             # remote / hybrid / onsite
      add_column table, :salary_min, :integer           # gross, in euros
      add_column table, :salary_max, :integer
      add_column table, :salary_period, :string, null: false, default: "month" # month / year
      add_index table, :work_mode
    end
  end
end
