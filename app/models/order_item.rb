class OrderItem < ApplicationRecord
  include Auditable

  belongs_to :order
  belongs_to :marketplace_listing, optional: true
  belongs_to :catalog_product, optional: true

  enum :item_status, { pending: 0, confirmed: 1, shipped: 2, delivered: 3, canceled: 4, returned: 5 }, default: :pending, validate: true

  validates :product_name_snapshot, presence: true
  validates :quantity, numericality: { greater_than: 0, only_integer: true }
  validates :unit_price_krw, numericality: { greater_than_or_equal_to: 0 }

  delegate :account, to: :order
end
