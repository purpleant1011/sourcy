class MarketplaceAccount < ApplicationRecord
  include AccountScoped
  include Auditable

  has_many :marketplace_listings, dependent: :destroy
  has_many :orders, dependent: :destroy

  enum :provider, { coupang: 0, naver_smartstore: 1, eleven_street: 2 }, validate: true
  enum :status, { active: 0, paused: 1, disabled: 2 }, default: :active, validate: true

  encrypts :credentials_ciphertext

  validates :shop_name, presence: true
  validates :shop_name, uniqueness: { scope: :account_id }
end
