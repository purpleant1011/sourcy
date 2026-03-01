class CreateMarketplaceListings < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_listings, id: :uuid do |t|
      t.references :catalog_product, null: false, type: :uuid, foreign_key: true
      t.references :marketplace_account, null: false, type: :uuid, foreign_key: true
      t.string :external_listing_id
      t.string :marketplace_category_code
      t.jsonb :marketplace_attributes, null: false, default: {}
      t.bigint :listed_price_krw, null: false
      t.integer :status, null: false, default: 0
      t.datetime :listed_at
      t.datetime :last_synced_at
      t.jsonb :sync_errors, null: false, default: []

      t.timestamps
    end

    add_index :marketplace_listings, [:marketplace_account_id, :status]
    add_index :marketplace_listings, [:marketplace_account_id, :external_listing_id], unique: true
    add_index :marketplace_listings, [:catalog_product_id, :marketplace_account_id], unique: true, name: :idx_marketplace_listings_uniqueness
  end
end
