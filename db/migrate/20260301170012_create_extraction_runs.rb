class CreateExtractionRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :extraction_runs, id: :uuid do |t|
      t.references :source_product, null: false, type: :uuid, foreign_key: true
      t.integer :provider, null: false
      t.string :input_hash, null: false
      t.jsonb :result, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.bigint :cost_cents, null: false, default: 0
      t.integer :duration_ms
      t.text :error_message

      t.timestamps
    end

    add_index :extraction_runs, [:source_product_id, :created_at]
    add_index :extraction_runs, [:provider, :input_hash]
    add_index :extraction_runs, :status, where: "status = 0"
  end
end
