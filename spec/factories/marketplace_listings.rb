# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_listing do
    catalog_product
    marketplace_account { |catalog_product| catalog_product.account.marketplace_accounts.first || create(:marketplace_account, account: catalog_product.account) }
    listed_price_krw { 15000 }
    status { :draft }

    trait :live do
      status { :live }
    end

    trait :paused do
      status { :paused }
    end

    trait :sync_failed do
      status { :sync_failed }
    end

    trait :closed do
      status { :closed }
    end
  end
end
