class Subscription < ApplicationRecord
  include AccountScoped
  include Auditable

  has_many :invoices, dependent: :destroy

  enum :plan, { free: 0, basic: 1, pro: 2, premium: 3 }, validate: true
  enum :status, { trialing: 0, active: 1, past_due: 2, canceled: 3 }, default: :trialing, validate: true

  # Alias for current_period_end (used in API responses)
  def expires_at
    current_period_end
  end

  # Alias for plan (used in API responses)
  def plan_name
    plan.to_s
  end
end
