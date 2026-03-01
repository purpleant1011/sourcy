class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.integer :plan, null: false
      t.integer :status, null: false, default: 0
      t.datetime :trial_ends_at
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.string :payment_provider
      t.string :external_subscription_id

      t.timestamps
    end

    add_index :subscriptions, [:account_id, :status]
    add_index :subscriptions, [:account_id, :external_subscription_id], unique: true
  end
end
