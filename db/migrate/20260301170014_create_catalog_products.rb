class CreateCatalogProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_products, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :source_product, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.string :translated_title, null: false
      t.text :translated_description
      t.jsonb :processed_images, null: false, default: []
      t.jsonb :category_tags, null: false, default: []
      t.bigint :base_price_krw, null: false
      t.bigint :cost_price_krw, null: false
      t.decimal :fx_rate_snapshot, precision: 12, scale: 4, null: false
      t.decimal :margin_percent, precision: 6, scale: 2, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :risk_flags, null: false, default: {}
      t.boolean :kc_cert_required, null: false, default: false
      t.integer :kc_cert_status, null: false, default: 0
      t.string :hs_code
      t.decimal :customs_duty_rate, precision: 6, scale: 3

      t.timestamps
    end

    add_index :catalog_products, [:account_id, :status]
    add_index :catalog_products, :risk_flags, using: :gin

    execute <<~SQL
      CREATE INDEX index_catalog_products_on_translated_title_tsv
      ON catalog_products USING gin (to_tsvector('simple', coalesce(translated_title, '')))
    SQL
  end
end
