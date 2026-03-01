class CreateSourceProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :source_products, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.integer :source_platform, null: false
      t.string :source_url, null: false
      t.string :source_id, null: false
      t.string :original_title, null: false
      t.text :original_description
      t.jsonb :original_images, null: false, default: []
      t.bigint :original_price_cents, null: false
      t.string :original_currency, null: false, default: "CNY"
      t.jsonb :raw_data, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.datetime :collected_at

      t.timestamps
    end

    add_index :source_products, [:account_id, :source_platform, :source_id], unique: true, name: :idx_source_products_account_source_uid
    add_index :source_products, [:account_id, :status]
    add_index :source_products, :source_url

    execute <<~SQL
      CREATE INDEX index_source_products_on_original_title_tsv
      ON source_products USING gin (to_tsvector('simple', coalesce(original_title, '')))
    SQL
  end
end
