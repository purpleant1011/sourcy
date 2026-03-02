FactoryBot.define do
  factory :alert do
    title { "MyString" }
    description { "MyText" }
    severity { 1 }
    source { "MyString" }
  end
end
