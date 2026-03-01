class WebhookEvent < ApplicationRecord
  include AccountScoped
  include Auditable

  enum :provider, { coupang: 0, naver_smartstore: 1, eleven_street: 2, portone: 3 }, validate: true
  enum :status, { pending: 0, processed: 1, failed: 2 }, default: :pending, validate: true

  validates :external_event_id, :event_type, presence: true
  validates :external_event_id, uniqueness: { scope: [:account_id, :provider] }

  scope :pending, -> { where(status: :pending) }
end
