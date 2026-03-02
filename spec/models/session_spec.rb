# frozen_string_literal: true

RSpec.describe Session, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
  end

  describe "validations" do
    subject { build(:session) }

    it { should validate_presence_of(:ip_address) }
    it { should allow_value("127.0.0.1").for(:ip_address) }
    it { should allow_value("192.168.1.1").for(:ip_address) }
    it { should allow_value("2001:0db8:85a3:0000:0000:8a2e:0370:7334").for(:ip_address) }
  end

  describe ".find_signed_by_id" do
    let(:session) { create(:session) }

    context "with valid signed ID" do
      it "finds the session" do
        signed_id = session.signed_id
        found_session = Session.find_signed_by_id(signed_id)

        expect(found_session).to eq(session)
      end

      it "finds the session with purpose" do
        session_with_purpose = create(:session, :api_token)
        signed_id = session_with_purpose.signed_id(purpose: "api_token")

        found_session = Session.find_signed_by_id(signed_id, purpose: "api_token")

        expect(found_session).to eq(session_with_purpose)
      end

      it "does not find session with wrong purpose" do
        session_with_purpose = create(:session, :api_token)
        signed_id = session_with_purpose.signed_id(purpose: "api_token")

        found_session = Session.find_signed_by_id(signed_id, purpose: "different_purpose")

        expect(found_session).to be_nil
      end
    end

    context "with invalid signed ID" do
      it "returns nil for invalid signature" do
        found_session = Session.find_signed_by_id("invalid_signed_id")

        expect(found_session).to be_nil
      end

      it "returns nil for blank string" do
        found_session = Session.find_signed_by_id("")

        expect(found_session).to be_nil
      end

      it "returns nil for nil" do
        found_session = Session.find_signed_by_id(nil)

        expect(found_session).to be_nil
      end
    end

    context "with non-existent ID" do
      skip "requires message_verifier configuration"
    end
  end

  describe "#signed_id" do
    context "with persisted session" do
      let(:session) { create(:session) }

      it "generates a signed ID" do
        signed_id = session.signed_id

        expect(signed_id).to be_present
        expect(signed_id).to be_a(String)
      end

      it "generates different signed IDs for different purposes" do
        signed_id_default = session.signed_id
        signed_id_api = session.signed_id(purpose: "api_token")

        expect(signed_id_default).not_to eq(signed_id_api)
      end

      it "generates consistent signed IDs for same purpose" do
        signed_id1 = session.signed_id(purpose: "api_token")
        signed_id2 = session.signed_id(purpose: "api_token")

        expect(signed_id1).to eq(signed_id2)
      end

      it "can be verified with find_signed_by_id" do
        signed_id = session.signed_id
        found_session = Session.find_signed_by_id(signed_id)

        expect(found_session).to eq(session)
      end
    end

    context "with unsaved session" do
      let(:session) { build(:session) }

      it "raises ArgumentError" do
        expect { session.signed_id }.to raise_error(ArgumentError, "Session must be saved before generating a signed ID")
      end
    end
  end

  describe "#expired?" do
    context "with expired session" do
      let(:session) { create(:session, :expired) }

      it "returns true" do
        expect(session.expired?).to be true
      end
    end

    context "with active session" do
      let(:session) { create(:session) }

      it "returns false" do
        expect(session.expired?).to be false
      end
    end

    context "with nil expires_at" do
      let(:session) { create(:session, expires_at: nil) }

      it "returns false" do
        expect(session.expired?).to be false
      end
    end

    context "at exact expiration time" do
      let(:session) { create(:session, expires_at: Time.current) }

      it "returns true" do
        # Use travel to ensure time consistency
        travel_to(Time.current) do
          expect(session.expired?).to be true
        end
      end
    end
  end

  describe "user association" do
    it "belongs to a user" do
      user = create(:user)
      session = create(:session, user: user)

      expect(session.user).to eq(user)
    end

    it "is destroyed when user is destroyed" do
      user = create(:user)
      session = create(:session, user: user)

      user.destroy

      expect { session.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "api_token purpose" do
    it "creates session with api_token purpose" do
      session = create(:session, :api_token)

      expect(session.purpose).to eq("api_token")
    end

    it "sets longer expiration for api_token" do
      session = create(:session, :api_token)

      expect(session.expires_at).to be > 23.hours.from_now
    end
  end

  describe "api_refresh purpose" do
    it "creates session with api_refresh purpose" do
      session = create(:session, :api_refresh)

      expect(session.purpose).to eq("api_refresh")
    end

    it "sets longer expiration for api_refresh" do
      session = create(:session, :api_refresh)

      expect(session.expires_at).to be > 29.days.from_now
    end
  end

  describe "user_agent" do
    it "stores user_agent string" do
      user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
      session = create(:session, user_agent: user_agent)

      expect(session.user_agent).to eq(user_agent)
    end
  end
end
