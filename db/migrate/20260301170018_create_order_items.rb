class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items, id: :uuid do |t|
      t.references :order, null: false, type: :uuid, foreign_key: true
      t.references :marketplace_listing, null: true, type: :uuid, foreign_key: true
      t.references :catalog_product, null: true, type: :uuid, foreign_key: true
      t.string :external_item_id
      t.string :product_name_snapshot, null: false
      t.integer :quantity, null: false
      t.bigint :unit_price_krw, null: false
      t.integer :item_status, null: false, default: 0

      t.timestamps
    end

    add_index :order_items, [:order_id, :external_item_id], unique: true, where: "external_item_id IS NOT NULL"
    add_index :order_items, [:order_id, :item_status]
  end
end
