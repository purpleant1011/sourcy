class ExtractionRun < ApplicationRecord
  include Auditable

  belongs_to :source_product
  has_many :translation_runs, dependent: :destroy

  enum :provider, { gpt: 0, claude: 1, gemini: 2 }, validate: true
  enum :status, { pending: 0, completed: 1, failed: 2 }, default: :pending, validate: true

  validates :input_hash, presence: true

  scope :pending, -> { where(status: :pending) }

  delegate :account, to: :source_product
end
