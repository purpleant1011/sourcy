# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    account
    marketplace_account

    external_order_id { "ORD#{SecureRandom.hex(6).upcase}" }
    ordered_at { Time.current }
    total_amount_krw { 15_000 }
    order_status { :pending }
    marketplace_platform { :coupang }

    buyer_name_ciphertext { "Test Buyer" }
    buyer_contact_ciphertext { "test@example.com" }
    buyer_address_ciphertext { "Seoul, Korea" }

    trait :with_items do
      after(:create) do |order|
        create_list(:order_item, 3, order: order)
      end
    end
  end
end
