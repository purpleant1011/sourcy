# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogProduct, type: :model do
  describe "concerns" do
    it { should be_account_scoped }
    it { should be_auditable }
  end

  describe "associations" do
    it { should belong_to(:source_product) }
    it { should have_many(:marketplace_listings).dependent(:destroy) }
    it { should have_many(:order_items).dependent(:nullify) }
  end

  describe "enums" do
    it do
      should define_enum_for(:status).with_values(draft: 0, listed: 1, paused: 2, archived: 3)
    end

    it do
      should define_enum_for(:kc_cert_status).
        with_values(unknown: 0, pending: 1, approved: 2, exempted: 3, rejected: 4)
    end
  end

  describe "validations" do
    subject { build(:catalog_product) }

    it { should validate_presence_of(:translated_title) }
    it { should validate_numericality_of(:base_price_krw).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:cost_price_krw).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:margin_percent).is_greater_than_or_equal_to(0) }
  end
end
