class AddMissingFieldsToSourceProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :source_products, :shop_name, :string
    add_column :source_products, :images, :jsonb
    add_column :source_products, :variants_data, :jsonb
    add_column :source_products, :specifications, :jsonb
  end
end
