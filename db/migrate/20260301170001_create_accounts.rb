class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :accounts, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :plan, null: false, default: 0
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :accounts, :slug, unique: true
    add_index :accounts, :plan
  end
end
