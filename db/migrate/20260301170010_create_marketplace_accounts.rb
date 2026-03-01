class CreateMarketplaceAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_accounts, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.integer :provider, null: false
      t.string :shop_name, null: false
      t.text :credentials_ciphertext
      t.integer :status, null: false, default: 0
      t.jsonb :rate_limit_config, null: false, default: {}

      t.timestamps
    end

    add_index :marketplace_accounts, [:account_id, :provider]
    add_index :marketplace_accounts, [:account_id, :shop_name], unique: true
  end
end
