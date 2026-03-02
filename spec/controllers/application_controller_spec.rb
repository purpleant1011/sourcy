# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      head :ok
    end
  end

  describe "before_action" do
    it "includes Authentication concern" do
      expect(described_class.ancestors).to include(Authentication)
    end

    it "authenticates user before every action" do
      expect(controller).to receive(:authenticate).and_call_original
      get :index
    end

    it "sets current context before every action" do
      expect(controller).to receive(:set_current_context).and_call_original
      get :index
    end

    it "sets current account before every action" do
      expect(controller).to receive(:set_current_account).and_call_original
      get :index
    end
  end

  describe "#set_current_context" do
    it "sets Current.ip_address to request.remote_ip" do
      allow(request).to receive(:remote_ip).and_return("127.0.0.1")

      controller.send(:set_current_context)

      expect(Current.ip_address).to eq("127.0.0.1")
    end

    context "with authenticated user" do
      let(:user) { create(:user) }

      before do
        Current.session = create(:session, user: user)
      end

      it "sets Current.user to session user" do
        controller.send(:set_current_context)

        expect(Current.user).to eq(user)
      end
    end

    context "without authenticated user" do
      it "does not set Current.user" do
        Current.session = nil
        controller.send(:set_current_context)

        expect(Current.user).to be_nil
      end
    end
  end

  describe "#set_current_account" do
    context "with authenticated user" do
      let(:user) { create(:user) }
      let(:account) { create(:account) }

      before do
        user.update(account: account)
        Current.user = user
      end

      it "sets Current.account to user's account" do
        controller.send(:set_current_account)

        expect(Current.account).to eq(account)
      end
    end

    context "without authenticated user" do
      it "does not set Current.account" do
        Current.user = nil
        controller.send(:set_current_account)

        expect(Current.account).to be_nil
      end
    end
  end

  describe "#current_user" do
    it "returns Current.user" do
      user = create(:user)
      Current.user = user

      expect(controller.current_user).to eq(user)
    end

    it "returns nil when no user is authenticated" do
      Current.user = nil

      expect(controller.current_user).to be_nil
    end
  end
end
