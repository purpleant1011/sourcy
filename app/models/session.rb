class Session < ApplicationRecord
  belongs_to :user

  validates :ip_address, presence: true
end
