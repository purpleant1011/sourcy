class Subscription < ApplicationRecord
  include AccountScoped
  include Auditable

  has_many :invoices, dependent: :destroy

  enum :plan, { free: 0, basic: 1, pro: 2, premium: 3 }, validate: true
  enum :status, { trialing: 0, active: 1, past_due: 2, canceled: 3 }, default: :trialing, validate: true

  validates :external_subscription_id, uniqueness: { scope: :account_id }, allow_blank: true
end
