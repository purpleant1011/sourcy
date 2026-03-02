# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { should belong_to(:account) }
    it { should have_many(:sessions).dependent(:destroy) }
    it { should have_many(:memberships).dependent(:destroy) }
    it { should have_many(:accounts).dependent(:nullify) }
    it { should have_many(:oauth_identities).dependent(:destroy) }
    it { should have_many(:api_credentials).dependent(:destroy) }
    it { should have_many(:audit_logs).dependent(:nullify) }
  end

  describe "enums" do
    it "defines role enum with valid values" do
      expect(User.roles).to eq({ owner: 0, admin: 1, staff: 2, read_only: 3 }.with_indifferent_access)
    end
  end

  describe "validations" do
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should allow_value("test@example.com").for(:email) }
    it { should allow_value("test+tag@example.com").for(:email) }
    it { should_not allow_value("invalid-email").for(:email) }
    it { should_not allow_value("test@").for(:email) }
    it { should_not allow_value("@example.com").for(:email) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(120) }

    it { should allow_value(nil).for(:api_token_digest) }
    it { should allow_value("test").for(:api_token_digest) }
    it { should validate_length_of(:api_token_digest).is_at_most(255) }
  end

  describe "password" do
    it "has_secure_password" do
      user = build(:user, password: "Password123!")
      expect(user.password_digest).to be_present
    end

    it "validates password confirmation" do
      user = build(:user, password: "Password123!", password_confirmation: "Different")
      expect(user).not_to be_valid
    end

    it "authenticates with correct password" do
      user = create(:user, password: "Password123!")
      expect(user.authenticate("Password123!")).to eq(user)
    end

    it "does not authenticate with incorrect password" do
      user = create(:user, password: "Password123!")
      expect(user.authenticate("WrongPassword")).to be_falsey
    end
  end

  describe "email normalization" do
    it "downcases email before saving" do
      user = create(:user, email: "TEST@EXAMPLE.COM")
      expect(user.email).to eq("test@example.com")
    end

    it "strips whitespace from email before saving" do
      user = create(:user, email: "  test@example.com  ")
      expect(user.email).to eq("test@example.com")
    end
  end

  describe "defaults" do
    it "defaults to staff role" do
      user = create(:user)
      expect(user.role).to eq("staff")
    end
  end

  describe "#owner?" do
    it "returns true for owner role" do
      user = build(:user, role: :owner)
      expect(user.owner?).to be true
    end

    it "returns false for non-owner roles" do
      user = build(:user, role: :admin)
      expect(user.owner?).to be false
    end
  end

  describe "#admin?" do
    it "returns true for admin role" do
      user = build(:user, role: :admin)
      expect(user.admin?).to be true
    end

    it "returns false for non-admin roles" do
      user = build(:user, role: :staff)
      expect(user.admin?).to be false
    end
  end

  describe "#staff?" do
    it "returns true for staff role" do
      user = build(:user, role: :staff)
      expect(user.staff?).to be true
    end

    it "returns false for non-staff roles" do
      user = build(:user, role: :admin)
      expect(user.staff?).to be false
    end
  end

  describe "#read_only?" do
    it "returns true for read_only role" do
      user = build(:user, role: :read_only)
      expect(user.read_only?).to be true
    end

    it "returns false for non-read_only roles" do
      user = build(:user, role: :staff)
      expect(user.read_only?).to be false
    end
  end

  describe "scope :active_api_tokens" do
    it "includes users with active api tokens" do
      user_with_active = create(:user, :with_api_token, api_token_expires_at: 1.week.from_now)
      user_with_expired = create(:user, :with_api_token, api_token_expires_at: 1.day.ago)
      user_without_token = create(:user)

      expect(User.active_api_tokens).to include(user_with_active)
      expect(User.active_api_tokens).not_to include(user_with_expired)
      expect(User.active_api_tokens).not_to include(user_without_token)
    end
  end
end
