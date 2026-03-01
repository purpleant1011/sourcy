class Membership < ApplicationRecord
  include Auditable

  belongs_to :user
  belongs_to :account

  enum :role, { owner: 0, admin: 1, staff: 2, read_only: 3 }, default: :staff, validate: true

  validates :user_id, uniqueness: { scope: :account_id }
end
