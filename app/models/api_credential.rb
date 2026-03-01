class ApiCredential < ApplicationRecord
  include AccountScoped
  include Auditable

  belongs_to :user

  encrypts :secret_key_digest

  validates :secret_key_digest, presence: true

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
end
