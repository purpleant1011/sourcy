class CreateTrackingEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :tracking_events, id: :uuid do |t|
      t.references :shipment, null: false, type: :uuid, foreign_key: true
      t.string :status, null: false
      t.string :description
      t.string :location
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :tracking_events, [:shipment_id, :occurred_at]
  end
end
