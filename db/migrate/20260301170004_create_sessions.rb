class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.inet :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :sessions, [:user_id, :created_at]
  end
end
