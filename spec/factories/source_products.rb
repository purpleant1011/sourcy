FactoryBot.define do
  factory :source_product do
    account
    source_platform { :taobao }
    source_url { "https://item.taobao.com/item.htm?id=123456789" }
    source_id { SecureRandom.hex(12) }
    original_title { "测试商品" }
    original_price_cents { 10000 }
    original_currency { "CNY" }
    original_description { "这是测试商品描述" }
    original_images { ["https://example.com/image1.jpg", "https://example.com/image2.jpg"] }
    raw_data { {} }
    status { :ready }
    collected_at { Time.current }

    trait :pending do
      status { :pending }
    end

    trait :ready do
      status { :ready }
    end

    trait :failed do
      status { :failed }
    end

    trait :archived do
      status { :archived }
    end

    trait :taobao do
      source_platform { :taobao }
    end

    trait :aliexpress do
      source_platform { :aliexpress }
    end

    trait :tmall do
      source_platform { :tmall }
    end

    trait :amazon do
      source_platform { :amazon }
      original_currency { "USD" }
    end
  end
end
