# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AuthController", type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, password: "Password123!") }

  describe "POST #login" do
    context "with valid credentials" do
      it "returns success with JWT token" do
        post :login, params: {
          email: user.email,
          password: "Password123!"
        }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["data"]["token"]).to be_present
        expect(json["data"]["user"]["id"]).to eq(user.id)
      end
    end

    context "with invalid credentials" do
      it "returns unauthorized error" do
        post :login, params: {
          email: user.email,
          password: "WrongPassword!"
        }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("AUTH_INVALID_CREDENTIALS")
      end
    end
  end

  describe "POST #refresh" do
    let(:session_record) { create(:session, user: user) }

    before do
      allow(controller).to receive(:bearer_token).and_return("valid_token")
      allow(controller).to receive(:decode_jwt!).and_return({
        "sub" => user.id,
        "account_id" => account.id,
        "sid" => session_record.id
      })
    end

    it "returns success with new JWT token" do
      post :refresh

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["data"]["token"]).to be_present
    end
  end

  describe "DELETE #logout" do
    let(:session_record) { create(:session, user: user) }

    before do
      allow(controller).to receive(:bearer_token).and_return("valid_token")
      allow(controller).to receive(:decode_jwt!).and_return({
        "sub" => user.id,
        "account_id" => account.id,
        "sid" => session_record.id
      })
    end

    it "terminates session and returns success" do
      expect {
        delete :logout
      }.to change(Session, :count).by(-1)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
    end
  end
end
