# frozen_string_literal: true

require "rails_helper"

RSpec.describe SourceProduct, type: :model do
  describe "concerns" do
    it { should be_account_scoped }
    it { should be_auditable }
  end

  describe "associations" do
    it { should belong_to(:account) }
    it { should have_many(:extraction_runs).dependent(:destroy) }
    it { should have_one(:catalog_product).dependent(:destroy) }
  end

  describe "enums" do
    it do
      should define_enum_for(:source_platform).with_values(taobao: 0, aliexpress: 1, tmall: 2, amazon: 3)
    end

    it do
      should define_enum_for(:status).with_values(pending: 0, ready: 1, failed: 2, archived: 3)
    end
  end

  describe "validations" do
    subject { build(:source_product) }

    it { should validate_presence_of(:source_url) }
    it { should validate_presence_of(:source_id) }
    it { should validate_presence_of(:original_title) }
    it { should validate_presence_of(:original_currency) }
    it { should validate_numericality_of(:original_price_cents).is_greater_than_or_equal_to(0) }
    it { should validate_uniqueness_of(:source_id).scoped_to(:account_id, :source_platform) }
  end

  describe "scopes" do
    it "orders products by collection date" do
      product1 = create(:source_product, collected_at: 2.days.ago)
      product2 = create(:source_product, collected_at: 1.day.ago)
      product3 = create(:source_product, collected_at: 3.days.ago)

      expect(SourceProduct.recent).to eq([product2, product1, product3])
    end
  end
end
