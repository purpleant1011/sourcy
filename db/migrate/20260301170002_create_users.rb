class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.integer :role, null: false, default: 0
      t.string :otp_secret
      t.string :api_token_digest
      t.datetime :api_token_expires_at
      t.datetime :confirmed_at
      t.datetime :last_sign_in_at
      t.inet :last_sign_in_ip

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, [:account_id, :role]
  end
end
