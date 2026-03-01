class AuditLog < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true

  validates :auditable_type, :auditable_id, :action, presence: true

  before_update :block_mutation
  before_destroy :block_mutation

  private

  def block_mutation
    errors.add(:base, "audit logs are append-only")
    throw(:abort)
  end
end
