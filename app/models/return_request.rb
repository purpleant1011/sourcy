class ReturnRequest < ApplicationRecord
  include Auditable

  belongs_to :order

  enum :status, { requested: 0, reviewing: 1, approved: 2, rejected: 3, refunded: 4 }, default: :requested, validate: true

  validates :reason_code, :requested_at, presence: true
  validates :order_id, uniqueness: true

  delegate :account, to: :order
end
