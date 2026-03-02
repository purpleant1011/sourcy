FactoryBot.define do
  factory :catalog_product do
    account
    source_product
    translated_title { "Test Product" }
    translated_description { "Test product description" }
    base_price_krw { 10000 }
    cost_price_krw { 5000 }
    margin_percent { 50.0 }
    fx_rate_snapshot { 1300.0 }
    trait :listed do
      status { :listed }
    end

    trait :active do
      status { :listed }
    end

    trait :archived do
      status { :archived }
    end
  end
end
