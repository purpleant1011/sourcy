class CreateCategoryMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :category_mappings do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.string :source_category, null: false
      t.integer :target_marketplace, null: false
      t.string :target_category_code, null: false
      t.string :target_category_name
      t.jsonb :attribute_mappings, null: false, default: {}

      t.timestamps
    end

    add_index :category_mappings, [:account_id, :source_category, :target_marketplace], unique: true, name: :idx_category_mappings_unique
    add_index :category_mappings, [:account_id, :target_marketplace]
  end
end
