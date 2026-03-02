class RenameChangesToAuditChangesInAuditLogs < ActiveRecord::Migration[8.1]
  def change
    rename_column :audit_logs, :changes, :audit_changes
  end
end
