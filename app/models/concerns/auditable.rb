module Auditable
  extend ActiveSupport::Concern

  included do
    after_create :audit_create_action
    after_update :audit_update_action
    after_destroy :audit_destroy_action
  end

  private

  def audit_create_action
    create_audit_log!("create", previous_changes.except("created_at", "updated_at"))
  end

  def audit_update_action
    tracked_changes = previous_changes.except("updated_at")
    return if tracked_changes.empty?

    create_audit_log!("update", tracked_changes)
  end

  def audit_destroy_action
    create_audit_log!("destroy", attributes)
  end

  def create_audit_log!(action, audited_changes)
    return unless self.class.connection.data_source_exists?("audit_logs")
    return unless Current.account

    AuditLog.create!(
      account: Current.account,
      user: Current.user,
      auditable_type: self.class.name,
      auditable_id: id,
      action: action,
      changes: audited_changes,
      ip_address: Current.ip_address
    )
  end
end
