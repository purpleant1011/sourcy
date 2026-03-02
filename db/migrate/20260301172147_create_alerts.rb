class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :alerts do |t|
      t.string :title
      t.text :description
      t.integer :severity
      t.string :source

      t.timestamps
    end
  end
end
