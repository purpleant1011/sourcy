class CreateCommissionRates < ActiveRecord::Migration[8.1]
  def change
    create_table :commission_rates do |t|
      t.integer :marketplace_platform, null: false
      t.string :category_code, null: false
      t.string :category_name, null: false
      t.decimal :rate_percent, precision: 6, scale: 3, null: false
      t.date :effective_from, null: false
      t.date :effective_until

      t.timestamps
    end

    add_index :commission_rates, [:marketplace_platform, :category_code, :effective_from], unique: true, name: :idx_commission_rates_unique_window
  end
end
