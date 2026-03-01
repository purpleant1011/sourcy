class KcCertRule < ApplicationRecord
  validates :product_category, presence: true, uniqueness: true
end
