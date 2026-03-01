class CatalogProduct < ApplicationRecord
  include AccountScoped
  include Auditable

  belongs_to :source_product
  has_many :marketplace_listings, dependent: :destroy
  has_many :order_items, dependent: :nullify

  enum :status, { draft: 0, listed: 1, paused: 2, archived: 3 }, default: :draft, validate: true
  enum :kc_cert_status, { unknown: 0, pending: 1, approved: 2, exempted: 3, rejected: 4 }, default: :unknown, validate: true

  validates :translated_title, presence: true
  validates :base_price_krw, :cost_price_krw, numericality: { greater_than_or_equal_to: 0 }
  validates :margin_percent, numericality: { greater_than_or_equal_to: 0 }

  scope :at_risk, -> { where("risk_flags <> '{}'::jsonb") }
end
