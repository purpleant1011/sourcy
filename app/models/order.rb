class Order < ApplicationRecord
  include AccountScoped
  include Auditable

  belongs_to :marketplace_account

  has_many :order_items, dependent: :destroy
  has_many :shipments, dependent: :destroy
  has_one :return_request, dependent: :destroy

  enum :marketplace_platform, { coupang: 0, naver_smartstore: 1, eleven_street: 2, portone: 3, gmarket: 4 }, validate: true
  enum :order_status, { pending: 0, paid: 1, preparing: 2, shipped: 3, delivered: 4, canceled: 5, returned: 6 }, default: :pending, validate: true

  encrypts :buyer_name_ciphertext
  encrypts :buyer_contact_ciphertext
  encrypts :buyer_address_ciphertext

  validates :external_order_id, presence: true
  validates :total_amount_krw, numericality: { greater_than_or_equal_to: 0 }
  validates :external_order_id, uniqueness: { scope: [:account_id, :marketplace_account_id] }

  scope :open_states, -> { where(order_status: %i[pending paid preparing shipped]) }
end
