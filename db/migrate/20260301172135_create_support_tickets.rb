class CreateSupportTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :support_tickets, id: :uuid do |t|
      t.uuid :user_id, null: true
      t.uuid :account_id, null: true
      t.uuid :order_id, null: true
      t.string :subject
      t.text :description
      t.integer :priority
      t.integer :status
      t.string :source

      t.timestamps
    end

    add_foreign_key :support_tickets, :users, column: :user_id, on_delete: :nullify
    add_foreign_key :support_tickets, :accounts, column: :account_id, on_delete: :nullify
    add_foreign_key :support_tickets, :orders, column: :order_id, on_delete: :nullify
  end
end
