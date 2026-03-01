class ListingVariant < ApplicationRecord
  include Auditable

  belongs_to :marketplace_listing

  validates :option_name, :option_value, presence: true
  validates :price_krw, numericality: { greater_than_or_equal_to: 0 }
  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  delegate :account, to: :marketplace_listing
end
