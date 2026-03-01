class Account < ApplicationRecord
  include Auditable

  belongs_to :owner, class_name: "User", optional: true

  has_many :users, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :api_credentials, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :marketplace_accounts, dependent: :destroy
  has_many :source_products, dependent: :destroy
  has_many :catalog_products, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :webhook_events, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :category_mappings, dependent: :destroy

  enum :plan, { free: 0, basic: 1, pro: 2, premium: 3 }, default: :free, validate: true

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
end
