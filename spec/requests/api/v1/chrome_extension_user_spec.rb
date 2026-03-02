# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::ChromeExtensionUser", type: :request do
  let(:user) { create(:user) }
  let(:account) { user.account }
  let(:session) { user.sessions.create!(user_agent: "Sourcy Chrome Extension", ip_address: "127.0.0.1") }

  def auth_header
    payload = {
      sub: user.id,
      account_id: user.account_id,
      sid: session.id,
      iat: Time.current.to_i,
      exp: 24.hours.from_now.to_i
    }
    token = JWT.encode(payload, Rails.application.credentials.jwt_secret || Rails.application.secret_key_base, "HS256")

    { "Authorization" => "Bearer #{token}", "Idempotency-Key" => SecureRandom.uuid }
  end

  describe "GET /api/v1/user" do
    context "with valid authentication" do
      it "returns user information" do
        get "/api/v1/user", headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["id"]).to eq(user.id)
        expect(json["data"]["email"]).to eq(user.email)
        expect(json["data"]["name"]).to eq(user.name)
        expect(json["data"]["role"]).to eq(user.role.to_s)
        expect(json["data"]["account_id"]).to eq(account.id)
        expect(json["data"]["account_name"]).to eq(account.name)
        expect(json["data"]["business_type"]).to eq(account.business_type.to_s)
        expect(json["data"]["status"]).to eq(account.status.to_s)
        expect(json["data"]["created_at"]).to be_present
      end

      it "includes usage statistics" do
        create_list(:source_product, 5, account: account)
        create_list(:catalog_product, 2, account: account, status: :listed)

        get "/api/v1/user", headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["data"]["usage"]).to be_present
        expect(json["data"]["usage"]["products_count"]).to eq(5)
        expect(json["data"]["usage"]["listed_count"]).to eq(2)
      end

      it "includes api_key" do
        get "/api/v1/user", headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["data"]["api_key"]).to be_present
        expect(json["data"]["api_key"]).to match(/^sk_e\.\.\.[a-f0-9]{4}$/)
      end

      it "includes subscription info if available" do
        create(:subscription, account: account, plan: :pro, status: :active)

        get "/api/v1/user", headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["data"]["subscription"]).to be_present
        expect(json["data"]["subscription"]["plan"]).to eq("pro")
        expect(json["data"]["subscription"]["status"]).to eq("active")
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/user"

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("AUTH_MISSING_TOKEN")
      end
    end
  end

  describe "PUT /api/v1/user" do
    context "with valid data" do
      it "updates user name" do
        put "/api/v1/user",
          params: { name: "Updated Name" },
          headers: auth_header,
          as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["name"]).to eq("Updated Name")

        user.reload
        expect(user.name).to eq("Updated Name")
      end

      it "updates password" do
        old_password_digest = user.password_digest

        put "/api/v1/user",
          params: {
            password: "new_password123",
            password_confirmation: "new_password123"
          },
          headers: auth_header,
          as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true

        user.reload
        expect(user.password_digest).not_to eq(old_password_digest)
        expect(user.authenticate("new_password123")).to be_truthy
      end
    end

    context "with invalid data" do
      it "returns validation error for password mismatch" do
        put "/api/v1/user",
          params: {
            password: "new_password123",
            password_confirmation: "different_password"
          },
          headers: auth_header,
          as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("VALIDATION_FAILED")
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        put "/api/v1/user",
          params: { name: "Test" },
          as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "PUT /api/v1/user/account" do
    context "with valid data" do
      it "updates account name" do
        put "/api/v1/user/account",
          params: { name: "Updated Store Name" },
          headers: auth_header,
          as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["name"]).to eq("Updated Store Name")

        account.reload
        expect(account.name).to eq("Updated Store Name")
      end

      it "updates business type" do
        put "/api/v1/user/account",
          params: { business_type: "company" },
          headers: auth_header,
          as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["business_type"]).to eq("company")

        account.reload
        expect(account.business_type).to eq("company")
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        put "/api/v1/user/account",
          params: { name: "Test" },
          as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
