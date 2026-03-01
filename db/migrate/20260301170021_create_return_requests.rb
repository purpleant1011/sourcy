class CreateReturnRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :return_requests, id: :uuid do |t|
      t.references :order, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.string :reason_code, null: false
      t.text :reason_detail
      t.integer :status, null: false, default: 0
      t.bigint :refund_amount_krw
      t.datetime :requested_at, null: false
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :return_requests, :status
  end
end
