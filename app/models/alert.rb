class Alert < ApplicationRecord

  enum :severity, { low: 0, medium: 1, high: 2, critical: 3 }, suffix: true
  enum :source, { system: 0, email: 1, api: 2, manual: 3 }

  validates :title, presence: true, length: { maximum: 255 }
  validates :severity, presence: true
  validates :source, presence: true

  scope :high_severity, -> { where(severity: [:high, :critical]) }
  scope :unread, -> { where(read_at: nil) }

  include AccountScoped, Auditable
end
