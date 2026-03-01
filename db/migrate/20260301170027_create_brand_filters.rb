class CreateBrandFilters < ActiveRecord::Migration[8.1]
  def change
    create_table :brand_filters do |t|
      t.string :keyword, null: false
      t.string :brand_name, null: false
      t.integer :action, null: false, default: 0
      t.string :category

      t.timestamps
    end

    add_index :brand_filters, [:keyword, :category], unique: true
    add_index :brand_filters, :action
  end
end
