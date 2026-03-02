# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Chrome Extension E2E Flow", type: :request do
  describe "Complete OAuth2 PKCE flow and product management" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:client_id) { 'sourcy-chrome-extension' }

    before do
      # Create subscription for account
      create(:subscription, account: account, plan: :free, status: :active)
    end
    let(:user) { create(:user, account: account) }
    let(:client_id) { 'sourcy-chrome-extension' }

    context "full flow from authorization to product management" do
      before do
        # Simulate Chrome Extension PKCE flow
        @code_challenge = "test_challenge_#{SecureRandom.hex(8)}"
        @code_verifier = @code_challenge  # plain method
        @redirect_uri = "https://sourcy.com/oauth/callback"
        @state = "test_state_#{SecureRandom.hex(4)}"

        # Step 1: Create authorization session (authorize endpoint would be called in real flow)
        auth_session_data = {
          code_challenge: @code_challenge,
          code_challenge_method: "plain",
          redirect_uri: @redirect_uri,
          state: @state,
          user_id: user.id,
          created_at: Time.current,
          expires_at: 10.minutes.from_now
        }

        @session_id = SecureRandom.uuid
        Rails.cache.write("oauth_code:#{@session_id}", auth_session_data, expires_in: 10.minutes)
        @authorization_code = @session_id
      end

      it "completes full OAuth2 PKCE flow and manages products" do
        # Step 2: Exchange authorization code for access token
        post "/api/v1/auth/token", params: {
          grant_type: "authorization_code",
          code: @authorization_code,
          code_verifier: @code_verifier,
          redirect_uri: @redirect_uri,
          client_id: client_id
        }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        access_token = json["data"]["access_token"]
        refresh_token = json["data"]["refresh_token"]

        expect(access_token).to be_present
        expect(refresh_token).to be_present

        # Step 3: Get current user info with access token
        auth_header = {
          "Authorization" => "Bearer #{access_token}",
          "Idempotency-Key" => SecureRandom.uuid
        }

        get "/api/v1/user", headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["id"]).to eq(user.id)
        expect(json["data"]["email"]).to eq(user.email)
        expect(json["data"]["subscription"]["plan"]).to eq("free")

        # Step 4: Create a source product
        product_data = {
          platform: "aliexpress", source_id: "aliexpress_product_123",
          shop_name: "AliExpress Official Store",
          title: "Test Product Title",
          description: "Test product description",
          price: 15000,
          url: "https://aliexpress.com/item/123",
          images: [ "https://example.com/image1.jpg", "https://example.com/image2.jpg" ],
          variants: [ { size: "M", color: "Red", price: 15000 } ],
          specifications: { weight: "500g", material: "Cotton" },
          currency: "KRW"
        }

        post "/api/v1/products/extract", params: product_data, headers: auth_header

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        source_product_id = json["data"]["id"]
        expect(json["data"]["title"]).to eq("Test Product Title")
        expect(json["data"]["status"]).to eq("pending")

        # Step 5: Get product list
        get "/api/v1/source_products", headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"].length).to eq(1)

        # Step 6: Update product status to ready
        patch "/api/v1/source_products/#{source_product_id}", params: {
          status: "ready"
        }, headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["status"]).to eq("ready")

        # Step 7: Get updated product list with stats
        expect(json["success"]).to be true
        expect(json["data"]["status"]).to eq("ready")

        # Step 7: Get updated product list with stats
        get "/api/v1/source_products", headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"].length).to eq(1)

        # Step 8: Delete product
        delete "/api/v1/source_products/#{source_product_id}", headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true

        # Step 9: Verify product is deleted
        get "/api/v1/source_products", headers: auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"].length).to eq(0)

        # Step 10: Refresh access token
        post "/api/v1/auth/token", params: {
          grant_type: "refresh_token",
          refresh_token: refresh_token,
          client_id: client_id
        }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        new_access_token = json["data"]["access_token"]
        new_refresh_token = json["data"]["refresh_token"]

        expect(new_access_token).to be_present
        expect(new_refresh_token).to be_present
        expect(new_access_token).not_to eq(access_token)  # Token should be rotated

        # Step 11: Verify new token works
        new_auth_header = {
          "Authorization" => "Bearer #{new_access_token}",
          "Idempotency-Key" => SecureRandom.uuid
        }

        get "/api/v1/user", headers: new_auth_header

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["id"]).to eq(user.id)

        # Step 12: Revoke token
        delete "/api/v1/auth/revoke", params: {
          token: new_refresh_token
        }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["revoked"]).to be true

        # Step 13: Verify revoked token cannot be used
        post "/api/v1/auth/token", params: {
          grant_type: "refresh_token",
          refresh_token: new_refresh_token,
          client_id: client_id
        }, as: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("INVALID_GRANT")
      end
    end

    context "S256 code challenge method" do
      let(:code_verifier) { SecureRandom.hex(32) }
      let(:code_challenge) { Digest::SHA256.base64digest(code_verifier) }

      it "successfully verifies S256 code challenge" do
        auth_session_data = {
          code_challenge: code_challenge,
          code_challenge_method: "S256",
          redirect_uri: "https://sourcy.com/oauth/callback",
          state: "test_state",
          user_id: user.id,
          created_at: Time.current,
          expires_at: 10.minutes.from_now
        }

        session_id = SecureRandom.uuid
        Rails.cache.write("oauth_code:#{session_id}", auth_session_data, expires_in: 10.minutes)

        post "/api/v1/auth/token", params: {
          grant_type: "authorization_code",
          code: session_id,
          code_verifier: code_verifier,
          redirect_uri: "https://sourcy.com/oauth/callback",
          client_id: client_id
        }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["access_token"]).to be_present
      end
    end

    context "invalid authorization code" do
      it "returns error for invalid code" do
        post "/api/v1/auth/token", params: {
          grant_type: "authorization_code",
          code: "invalid_code",
          code_verifier: "test_verifier",
          redirect_uri: "https://sourcy.com/oauth/callback",
          client_id: client_id
        }, as: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("INVALID_GRANT")
      end
    end

    context "invalid access token" do
      it "returns error for invalid access token" do
        auth_header = {
          "Authorization" => "Bearer invalid_token",
          "Idempotency-Key" => SecureRandom.uuid
        }

        get "/api/v1/user", headers: auth_header

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("AUTH_INVALID_TOKEN")
      end
    end

    context "multi-account isolation" do
      let(:account2) { create(:account) }
      let(:user2) { create(:user, account: account2) }

      before do
        # Create auth session for user1
        auth_session_data = {
          code_challenge: "challenge1",
          code_challenge_method: "plain",
          redirect_uri: "https://sourcy.com/oauth/callback",
          state: "state1",
          user_id: user.id,
          created_at: Time.current,
          expires_at: 10.minutes.from_now
        }

        @session_id1 = SecureRandom.uuid
        Rails.cache.write("oauth_code:#{@session_id1}", auth_session_data, expires_in: 10.minutes)

        # Create auth session for user2
        auth_session_data2 = {
          code_challenge: "challenge2",
          code_challenge_method: "plain",
          redirect_uri: "https://sourcy.com/oauth/callback",
          state: "state2",
          user_id: user2.id,
          created_at: Time.current,
          expires_at: 10.minutes.from_now
        }

        @session_id2 = SecureRandom.uuid
        Rails.cache.write("oauth_code:#{@session_id2}", auth_session_data2, expires_in: 10.minutes)
      end

      it "ensures proper data isolation between accounts" do
        # Get tokens for user1
        post "/api/v1/auth/token", params: {
          grant_type: "authorization_code",
          code: @session_id1,
          code_verifier: "challenge1",
          redirect_uri: "https://sourcy.com/oauth/callback",
          client_id: client_id
        }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        token1 = json["data"]["access_token"]

        # Get tokens for user2
        post "/api/v1/auth/token", params: {
          grant_type: "authorization_code",
          code: @session_id2,
          code_verifier: "challenge2",
          redirect_uri: "https://sourcy.com/oauth/callback",
          client_id: client_id
        }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        token2 = json["data"]["access_token"]

        # User1 creates product
        auth_header1 = {
          "Authorization" => "Bearer #{token1}",
          "Idempotency-Key" => SecureRandom.uuid
        }

        post "/api/v1/products/extract", params: {
          platform: "aliexpress", source_id: "product1",
          shop_name: "Store1",
          title: "Product 1",
          description: "Description 1",
          price: 10000,
          currency: "KRW",
          url: "https://example.com/product1"
        }, headers: auth_header1

        expect(response).to have_http_status(:created)
        # User2 creates product
        auth_header2 = {
          "Authorization" => "Bearer #{token2}",
          "Idempotency-Key" => SecureRandom.uuid
        }
        post "/api/v1/products/extract", params: {
          platform: "aliexpress", source_id: "product2",
          shop_name: "Store2",
          title: "Product 2",
          description: "Description 2",
          price: 20000,
          currency: "KRW",
          url: "https://example.com/product2"
        }, headers: auth_header2

        expect(response).to have_http_status(:created)
        # User1 sees only their product
        get "/api/v1/source_products", headers: auth_header1

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"].length).to eq(1)
        expect(json["data"][0]["title"]).to eq("Product 1")

        # User2 sees only their product
        get "/api/v1/source_products", headers: auth_header2

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"].length).to eq(1)
        expect(json["data"][0]["title"]).to eq("Product 2")
      end
    end
  end
end
