FactoryBot.define do
  factory :support_ticket do
    user { nil }
    account { nil }
    subject { "MyString" }
    description { "MyText" }
    priority { 1 }
    status { 1 }
    order_id { "" }
    source { "MyString" }
  end
end
