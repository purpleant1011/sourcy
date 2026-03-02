FactoryBot.define do
  factory :account do
    name { "Test Account" }
    slug { "test-#{SecureRandom.hex(8)}" }
    plan { :free }
    settings { {} }

    trait :with_owner do
      owner
    end

    trait :basic do
      plan { :basic }
    end

    trait :pro do
      plan { :pro }
    end

    trait :premium do
      plan { :premium }
    end
  end
end
