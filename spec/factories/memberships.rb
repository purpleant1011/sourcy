# frozen_string_literal: true

FactoryBot.define do
  factory :membership do
    account
    user
    role { :staff }

    trait :owner do
      role { :owner }
    end

    trait :admin do
      role { :admin }
    end

    trait :staff do
      role { :staff }
    end

    trait :read_only do
      role { :read_only }
    end
  end
end
