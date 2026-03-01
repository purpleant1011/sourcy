class CreateFxRateSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :fx_rate_snapshots do |t|
      t.string :currency_pair, null: false
      t.decimal :rate, precision: 12, scale: 4, null: false
      t.string :source_api, null: false
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :fx_rate_snapshots, [:currency_pair, :captured_at], unique: true
  end
end
