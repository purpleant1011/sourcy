# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscription, type: :model do
  describe "concerns" do
    it { should be_account_scoped }
    it { should be_auditable }
  end

  describe "associations" do
    it { should belong_to(:account) }
    it { should have_many(:invoices).dependent(:destroy) }
  end

  describe "enums" do
    it do
      should define_enum_for(:plan).with_values(free: 0, basic: 1, pro: 2, premium: 3)
    end

    it do
      should define_enum_for(:status).with_values(trialing: 0, active: 1, past_due: 2, canceled: 3)
    end
  end

  describe "defaults" do
    it "defaults to trialing status" do
      subscription = create(:subscription)
      expect(subscription.status).to eq("trialing")
    end
  end

  describe "#expires_at" do
    it "aliases current_period_end" do
      subscription = build(:subscription, current_period_end: Date.today)
      expect(subscription.expires_at).to eq(Date.today)
    end
  end

  describe "#plan_name" do
    it "aliases plan as string" do
      subscription = build(:subscription, plan: :pro)
      expect(subscription.plan_name).to eq("pro")
    end
  end
end
