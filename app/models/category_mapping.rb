class CategoryMapping < ApplicationRecord
  include AccountScoped
  include Auditable

  enum :target_marketplace, { coupang: 0, naver_smartstore: 1, eleven_street: 2 }, validate: true

  validates :source_category, :target_category_code, presence: true
  validates :source_category, uniqueness: { scope: [:account_id, :target_marketplace] }
end
