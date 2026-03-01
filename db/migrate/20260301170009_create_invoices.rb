class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices, id: :uuid do |t|
      t.references :subscription, null: false, type: :uuid, foreign_key: true
      t.bigint :amount_krw, null: false
      t.integer :status, null: false, default: 0
      t.datetime :issued_at
      t.datetime :paid_at
      t.string :pg_transaction_id

      t.timestamps
    end

    add_index :invoices, [:subscription_id, :status]
    add_index :invoices, :pg_transaction_id, unique: true
  end
end
