class CreateKcCertRules < ActiveRecord::Migration[8.1]
  def change
    create_table :kc_cert_rules do |t|
      t.string :product_category, null: false
      t.boolean :cert_required, null: false, default: true
      t.string :cert_type
      t.jsonb :exemption_conditions, null: false, default: {}
      t.string :reference_law

      t.timestamps
    end

    add_index :kc_cert_rules, :product_category, unique: true
  end
end
