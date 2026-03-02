FactoryBot.define do
  factory :user do
    account
    name { "Test User" }
    email { "user#{SecureRandom.hex(4)}@example.com" }
    password { "Password123!" }
    password_confirmation { "Password123!" }
    role { :staff }
    confirmed_at { Time.current }

    trait :owner do
      role { :owner }
    end

    trait :admin do
      role { :admin }
    end

    trait :staff do
      role { :staff }
    end

    trait :readonly do
      role { :readonly }
    end

    trait :with_api_token do
      api_token_digest { Digest::SHA256.hexdigest("test-api-token") }
      api_token_expires_at { 1.week.from_now }
    end

    trait :unconfirmed do
      confirmed_at { nil }
    end
  end
end
