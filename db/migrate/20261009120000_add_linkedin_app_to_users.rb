class AddLinkedinAppToUsers < ActiveRecord::Migration[8.1]
  def change
    # Does the user have the LinkedIn app? nil = not asked yet, true = open searches in the app,
    # false = open them in the browser.
    add_column :users, :linkedin_app, :boolean
  end
end
