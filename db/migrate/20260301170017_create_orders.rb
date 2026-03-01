class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :marketplace_account, null: false, type: :uuid, foreign_key: true
      t.string :external_order_id, null: false
      t.integer :marketplace_platform, null: false
      t.integer :order_status, null: false, default: 0
      t.datetime :ordered_at, null: false
      t.bigint :total_amount_krw, null: false
      t.text :buyer_name_ciphertext
      t.text :buyer_contact_ciphertext
      t.text :buyer_address_ciphertext
      t.text :shipping_memo

      t.timestamps
    end

    add_index :orders, [:account_id, :marketplace_account_id, :external_order_id], unique: true, name: :idx_orders_account_external_id
    add_index :orders, [:account_id, :ordered_at]
    add_index :orders, [:account_id, :order_status]
    add_index :orders, [:account_id, :ordered_at], where: "order_status IN (0, 1, 2)", name: :idx_orders_account_active_window
  end
end
