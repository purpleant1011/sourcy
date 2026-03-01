class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :user, null: true, type: :uuid, foreign_key: true
      t.string :auditable_type, null: false
      t.uuid :auditable_id, null: false
      t.string :action, null: false
      t.jsonb :changes, null: false, default: {}
      t.inet :ip_address

      t.timestamps
    end

    add_index :audit_logs, [:account_id, :created_at]
    add_index :audit_logs, [:account_id, :auditable_type, :auditable_id]
    add_index :audit_logs, [:account_id, :action]
  end
end
