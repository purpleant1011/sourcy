class OauthIdentity < ApplicationRecord
  include Auditable

  belongs_to :user

  enum :provider, { kakao: 0, naver: 1, google: 2 }, validate: true

  encrypts :access_token_ciphertext
  encrypts :refresh_token_ciphertext

  validates :uid, presence: true
  validates :provider, presence: true
  validates :uid, uniqueness: { scope: :provider }
end
