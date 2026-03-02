class Account < ApplicationRecord
  include Auditable

  belongs_to :owner, class_name: "User", optional: true

  has_many :users, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :api_credentials, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_one :current_subscription, -> { active }, class_name: 'Subscription', dependent: :destroy
  has_many :marketplace_accounts, dependent: :destroy
  has_many :source_products, dependent: :destroy
  has_many :catalog_products, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :webhook_events, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :category_mappings, dependent: :destroy

  enum :plan, { free: 0, basic: 1, pro: 2, premium: 3 }, default: :free, validate: true

  # Alias for plan (used in API responses)
  def status
    plan
  end

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }

  # Settings JSONB helpers
  def business_type
    settings["business_type"] || "individual"
  end

  # Get a setting value from settings JSONB
  def get_setting(key)
    settings[key.to_s]
  end

  # Set a setting value in settings JSONB
  def set_setting(key, value)
    update_column(:settings, settings.merge(key.to_s => value))
  end

  # Update business_type (settings setter for API)
  def business_type=(value)
    set_setting(:business_type, value)
  end
end
