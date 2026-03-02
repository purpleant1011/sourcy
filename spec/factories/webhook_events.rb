# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_event do
    account
    external_event_id { "test_event_#{SecureRandom.hex(8)}" }
    event_type { "order.created" }
    status { :pending }
    provider { :coupang }
    payload { {} }

    trait :processed do
      status { :processed }
    end

    trait :failed do
      status { :failed }
    end
  end
end
