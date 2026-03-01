class TranslationRun < ApplicationRecord
  include Auditable

  belongs_to :extraction_run

  enum :provider, { gpt: 0, deepl: 1, papago: 2 }, validate: true
  enum :status, { pending: 0, completed: 1, failed: 2 }, default: :pending, validate: true

  validates :source_lang, :target_lang, :input_text, :input_hash, presence: true

  scope :pending, -> { where(status: :pending) }

  delegate :source_product, :account, to: :extraction_run
end
