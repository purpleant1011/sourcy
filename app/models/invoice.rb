class Invoice < ApplicationRecord
  include Auditable

  belongs_to :subscription

  enum :status, { pending: 0, paid: 1, failed: 2, refunded: 3 }, default: :pending, validate: true

  validates :amount_krw, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :pg_transaction_id, uniqueness: true, allow_blank: true

  delegate :account, to: :subscription
end
