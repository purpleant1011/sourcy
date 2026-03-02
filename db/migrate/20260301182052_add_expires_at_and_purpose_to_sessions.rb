class AddExpiresAtAndPurposeToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :expires_at, :datetime
    add_column :sessions, :purpose, :string
  end
end
