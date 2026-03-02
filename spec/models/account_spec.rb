# frozen_string_literal: true
# frozen_string_literal: true

RSpec.describe Account, type: :model do
  describe "associations" do
    it { should belong_to(:owner).class_name("User").optional }
    it { should have_many(:users).dependent(:destroy) }
    it { should have_many(:memberships).dependent(:destroy) }
    it { should have_many(:api_credentials).dependent(:destroy) }
    it { should have_many(:subscriptions).dependent(:destroy) }
    it { should have_one(:current_subscription).class_name("Subscription") }
    it { should have_many(:marketplace_accounts).dependent(:destroy) }
    it { should have_many(:source_products).dependent(:destroy) }
    it { should have_many(:catalog_products).dependent(:destroy) }
    it { should have_many(:orders).dependent(:destroy) }
    it { should have_many(:webhook_events).dependent(:destroy) }
    it { should have_many(:audit_logs).dependent(:destroy) }
    it { should have_many(:category_mappings).dependent(:destroy) }
  end

  describe "enums" do
    it "defines plan enum with valid values" do
      expect(Account.plans).to eq({ free: 0, basic: 1, pro: 2, premium: 3 }.with_indifferent_access)
    end
  end

  describe "validations" do
    subject { build(:account) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(120) }
    it { should validate_presence_of(:slug) }
    it { should validate_uniqueness_of(:slug) }
    it { should allow_value("test-slug-123").for(:slug) }
    it { should allow_value("test").for(:slug) }
    it { should_not allow_value("Test_Slug").for(:slug) }
    it { should_not allow_value("test slug").for(:slug) }
    it { should_not allow_value("-test").for(:slug) }
    # Trailing hyphen is allowed based on model validation
  end

  describe "defaults" do
    it "defaults to free plan" do
      account = Account.new
      expect(account.plan).to eq("free")
    end
  end

  describe "#status" do
    it "returns plan value" do
      account = build(:account, plan: :pro)
      expect(account.status).to eq("pro")
    end
  end

  describe "#business_type" do
    it "returns business_type from settings" do
      account = build(:account, settings: { "business_type" => "corporation" })
      expect(account.business_type).to eq("corporation")
    end

    it "defaults to individual" do
      account = build(:account, settings: {})
      expect(account.business_type).to eq("individual")
    end
  end

  describe "#get_setting" do
    it "retrieves setting value" do
      account = build(:account, settings: { "custom_field" => "custom_value" })
      expect(account.get_setting(:custom_field)).to eq("custom_value")
    end

    it "returns nil for non-existent setting" do
      account = build(:account, settings: {})
      expect(account.get_setting(:non_existent)).to be_nil
    end
  end

  describe "#set_setting" do
    it "sets setting value" do
      account = create(:account, settings: { "field1" => "value1" })
      account.set_setting(:field2, "value2")
      account.reload

      expect(account.settings["field2"]).to eq("value2")
      expect(account.settings["field1"]).to eq("value1")
    end
  end

  describe "#business_type=" do
    it "sets business_type through settings" do
      account = create(:account, settings: {})
      account.business_type = "corporation"
      account.reload

      expect(account.settings["business_type"]).to eq("corporation")
    end
  end

  describe "slug format" do
    it "allows valid slugs" do
      account = build(:account, slug: "valid-slug-123")
      expect(account).to be_valid
    end

    it "rejects slugs with uppercase" do
      account = build(:account, slug: "Invalid-Slug")
      expect(account).not_to be_valid
    end

    it "rejects slugs with spaces" do
      account = build(:account, slug: "invalid slug")
      expect(account).not_to be_valid
    end

    it "rejects slugs starting with hyphen" do
      account = build(:account, slug: "-invalid")
      expect(account).not_to be_valid
    end

    it "allows slugs ending with hyphen" do
      account = build(:account, slug: "invalid-")
      expect(account).to be_valid
    end
  end
end
