class Session < ApplicationRecord
  belongs_to :user

  validates :ip_address, presence: true

  # Find a session by its signed ID with a specific purpose
  # This is used for token validation in the Chrome Extension API
  def self.find_signed_by_id(signed_id, purpose: nil)
    return nil if signed_id.blank?

    begin
      decoded = Rails.application.message_verifier(purpose: purpose).verify(signed_id)
      find(decoded)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      nil
    end
  end

  # Generate a signed ID for this session
  def signed_id(purpose: nil)
    raise ArgumentError, "Session must be saved before generating a signed ID" if new_record?
    Rails.application.message_verifier(purpose: purpose).generate(id)
  end

  # Check if the session is expired
  def expired?
    return false if expires_at.nil?
    expires_at <= Time.current
  end
end
