class MarketplaceListing < ApplicationRecord
  include Auditable

  belongs_to :catalog_product
  belongs_to :marketplace_account

  has_many :listing_variants, dependent: :destroy
  has_many :order_items, dependent: :nullify

  enum :status, { draft: 0, live: 1, paused: 2, sync_failed: 3, closed: 4 }, default: :draft, validate: true

  validates :listed_price_krw, numericality: { greater_than_or_equal_to: 0 }

  delegate :account, to: :marketplace_account
end
