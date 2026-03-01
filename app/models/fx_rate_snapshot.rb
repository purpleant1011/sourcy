class FxRateSnapshot < ApplicationRecord
  validates :currency_pair, :source_api, :captured_at, presence: true
  validates :rate, numericality: { greater_than: 0 }

  scope :recent_first, -> { order(captured_at: :desc) }
end
