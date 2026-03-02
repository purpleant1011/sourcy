class SupportTicket < ApplicationRecord
  include AccountScoped, Auditable

  belongs_to :user, optional: true
  belongs_to :order, optional: true
  has_many :attachments, as: :attachable, class_name: 'ActiveStorage::Attachment'

  enum :priority, { low: 0, normal: 1, high: 2, urgent: 3 }, suffix: true
  enum :status, { open: 0, in_progress: 1, resolved: 2, closed: 3 }, suffix: true
  enum :source, { email: 0, web: 1, api: 2 }

  validates :subject, presence: true, length: { maximum: 255 }
  validates :description, presence: true
  validates :priority, presence: true
  validates :status, presence: true

  scope :open, -> { where(status: :open) }
  scope :resolved, -> { where(status: :resolved) }
  scope :high_priority, -> { where(priority: [:high, :urgent]) }
  scope :by_account, ->(account) { where(account: account) }

  end
