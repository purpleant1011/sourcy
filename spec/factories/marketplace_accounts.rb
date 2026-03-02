# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_account do
    account
    provider { :coupang }
    shop_name { "Test Shop #{SecureRandom.hex(4)}" }
    credentials_ciphertext { "encrypted_credentials" }
    status { :active }

    trait :paused do
      status { :paused }
    end

    trait :disabled do
      status { :disabled }
    end
  end
end
