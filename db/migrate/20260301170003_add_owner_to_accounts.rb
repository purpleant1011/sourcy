class AddOwnerToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounts, :owner, null: true, type: :uuid, foreign_key: { to_table: :users }
  end
end
