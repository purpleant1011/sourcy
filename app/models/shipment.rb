class Shipment < ApplicationRecord
  include Auditable

  belongs_to :order
  has_many :tracking_events, dependent: :destroy

  enum :shipping_provider, { cj_logistics: 0, hanjin: 1, lotte: 2, epost: 3 }, validate: true
  enum :shipping_status, { ready: 0, in_transit: 1, delivered: 2, exception: 3 }, default: :ready, validate: true

  validates :shipping_cost_krw, numericality: { greater_than_or_equal_to: 0 }

  delegate :account, to: :order
end
