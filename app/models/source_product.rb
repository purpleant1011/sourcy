class SourceProduct < ApplicationRecord
  include AccountScoped
  include Auditable

  has_many :extraction_runs, dependent: :destroy
  has_one :catalog_product, dependent: :destroy

  enum :source_platform, { taobao: 0, aliexpress: 1, tmall: 2, amazon: 3 }, validate: true
  enum :status, { pending: 0, ready: 1, failed: 2, archived: 3 }, default: :pending, validate: true

  validates :source_url, :source_id, :original_title, :original_currency, presence: true
  validates :original_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :source_id, uniqueness: { scope: [:account_id, :source_platform] }

  scope :recent, -> { order(collected_at: :desc) }
end
