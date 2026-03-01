class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.integer :provider, null: false
      t.string :external_event_id, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.datetime :processed_at
      t.text :error_message

      t.timestamps
    end

    add_index :webhook_events, [:account_id, :provider, :external_event_id], unique: true, name: :idx_webhook_events_idempotency
    add_index :webhook_events, [:account_id, :status]
    add_index :webhook_events, [:account_id, :created_at], where: "processed_at IS NULL", name: :idx_webhook_events_pending
  end
end
