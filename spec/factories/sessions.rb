FactoryBot.define do
  factory :session do
    user
    ip_address { "127.0.0.1" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" }
    expires_at { 24.hours.from_now }
    purpose { nil }

    trait :api_token do
      purpose { "api_token" }
      expires_at { 24.hours.from_now }
    end

    trait :api_refresh do
      purpose { "api_refresh" }
      expires_at { 30.days.from_now }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end
  end
end
