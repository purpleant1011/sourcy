class CreateTranslationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :translation_runs, id: :uuid do |t|
      t.references :extraction_run, null: false, type: :uuid, foreign_key: true
      t.integer :provider, null: false
      t.string :source_lang, null: false
      t.string :target_lang, null: false
      t.text :input_text, null: false
      t.string :input_hash, null: false
      t.text :output_text
      t.integer :status, null: false, default: 0
      t.bigint :cost_cents, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :translation_runs, [:extraction_run_id, :created_at]
    add_index :translation_runs, [:provider, :input_hash]
    add_index :translation_runs, :status, where: "status = 0"
  end
end
