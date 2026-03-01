class CreateOauthIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_identities, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.integer :provider, null: false
      t.string :uid, null: false
      t.text :access_token_ciphertext
      t.text :refresh_token_ciphertext
      t.datetime :expires_at

      t.timestamps
    end

    add_index :oauth_identities, [:user_id, :provider], unique: true
    add_index :oauth_identities, [:provider, :uid], unique: true
  end
end
