class TrackingEvent < ApplicationRecord
  include Auditable

  belongs_to :shipment

  validates :status, :occurred_at, presence: true

  scope :chronological, -> { order(occurred_at: :asc) }

  delegate :order, :account, to: :shipment
end
