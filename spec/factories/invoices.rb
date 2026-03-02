# frozen_string_literal: true

FactoryBot.define do
  factory :invoice do
    subscription
    amount_krw { 10000 }
    pg_transaction_id { "pg_txn_#{SecureRandom.hex(8)}" }
    status { :pending }

    trait :paid do
      status { :paid }
    end

    trait :failed do
      status { :failed }
    end

    trait :refunded do
      status { :refunded }
    end
  end
end
