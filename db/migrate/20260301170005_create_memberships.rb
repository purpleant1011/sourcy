class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.integer :role, null: false, default: 2

      t.timestamps
    end

    add_index :memberships, [:account_id, :role]
    add_index :memberships, [:user_id, :account_id], unique: true
  end
end
