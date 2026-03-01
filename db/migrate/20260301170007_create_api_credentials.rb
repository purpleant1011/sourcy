class CreateApiCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :api_credentials, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :secret_key_digest, null: false
      t.datetime :last_used_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :api_credentials, [:account_id, :user_id]
    add_index :api_credentials, [:account_id, :expires_at]
  end
end
