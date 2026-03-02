FactoryBot.define do
  factory :subscription do
    account
    plan { :basic }
    status { :trialing }

    trait :active do
      status { :active }
    end

    trait :pro do
      plan { :pro }
      status { :active }
    end

    trait :premium do
      plan { :premium }
      status { :active }
    end

    trait :canceled do
      status { :canceled }
    end

    trait :past_due do
      status { :past_due }
    end
  end
end
