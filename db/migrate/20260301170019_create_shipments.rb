class CreateShipments < ActiveRecord::Migration[8.1]
  def change
    create_table :shipments, id: :uuid do |t|
      t.references :order, null: false, type: :uuid, foreign_key: true
      t.integer :shipping_provider, null: false
      t.string :tracking_number
      t.integer :shipping_status, null: false, default: 0
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.bigint :shipping_cost_krw, null: false, default: 0

      t.timestamps
    end

    add_index :shipments, [:order_id, :shipping_status]
    add_index :shipments, :tracking_number
  end
end
