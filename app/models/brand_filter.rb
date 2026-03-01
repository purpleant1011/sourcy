class BrandFilter < ApplicationRecord
  enum :action, { warn: 0, block: 1 }, default: :warn, validate: true

  validates :keyword, :brand_name, presence: true
end
