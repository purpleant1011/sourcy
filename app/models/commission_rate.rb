class CommissionRate < ApplicationRecord
  enum :marketplace_platform, { coupang: 0, naver_smartstore: 1, eleven_street: 2 }, validate: true

  validates :category_code, :category_name, :effective_from, presence: true
  validates :rate_percent, numericality: { greater_than_or_equal_to: 0 }

  scope :effective_on, ->(date) { where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", date, date) }
end
