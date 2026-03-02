class User < ApplicationRecord
  has_secure_password
  include Auditable

  belongs_to :account

  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :accounts, foreign_key: :owner_id, inverse_of: :owner, dependent: :nullify
  has_many :oauth_identities, dependent: :destroy
  has_many :api_credentials, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  enum :role, { owner: 0, admin: 1, staff: 2, read_only: 3 }, default: :staff, validate: true

  encrypts :otp_secret

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 120 }
  validates :api_token_digest, length: { maximum: 255 }, allow_blank: true

  scope :active_api_tokens, -> { where("api_token_expires_at > ?", Time.current) }
end
