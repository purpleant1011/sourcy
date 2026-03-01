class CreateListingVariants < ActiveRecord::Migration[8.1]
  def change
    create_table :listing_variants, id: :uuid do |t|
      t.references :marketplace_listing, null: false, type: :uuid, foreign_key: true
      t.string :external_variant_id
      t.string :option_name, null: false
      t.string :option_value, null: false
      t.bigint :price_krw, null: false
      t.integer :stock_quantity, null: false, default: 0
      t.string :sku

      t.timestamps
    end

    add_index :listing_variants, [:marketplace_listing_id, :external_variant_id], unique: true, where: "external_variant_id IS NOT NULL", name: :idx_listing_variants_external_id
    add_index :listing_variants, [:marketplace_listing_id, :sku], unique: true, where: "sku IS NOT NULL"
  end
end
