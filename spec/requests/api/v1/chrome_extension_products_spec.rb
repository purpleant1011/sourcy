# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::ChromeExtensionProducts", type: :request do
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

    {
      "Authorization" => "Bearer #{token}",
      "Idempotency-Key" => SecureRandom.uuid
    }
  end

  describe "POST /api/v1/products/extract" do
    context "with valid product data" do
      it "creates new product" do
        product_data = {
          platform: "taobao",
          source_id: "123456789",
          title: "Test Product",
          price: 99.99,
          currency: "CNY",
          url: "https://item.taobao.com/item.htm?id=123456789",
          description: "Test description",
          shop_name: "Test Shop",
          images: ["url1", "url2"],
          variants: [
            { name: "Color", values: ["Red", "Blue"] }
          ],
          specifications: {
            weight: "1kg"
          },
          collected_at: Time.current.iso8601
        }

        expect {
          post "/api/v1/products/extract",
            params: product_data,
            headers: auth_header,
            as: :json
        }.to change(SourceProduct, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["platform"]).to eq("taobao")
        expect(json["data"]["source_id"]).to eq("123456789")
        expect(json["data"]["title"]).to eq("Test Product")
        expect(json["data"]["price"]).to eq(99.99)
        expect(json["data"]["currency"]).to eq("CNY")
        expect(json["data"]["status"]).to eq("pending")
      end

      it "updates existing product" do
        existing_product = create(:source_product,
          account: account,
          source_platform: :taobao,
          source_id: "123456789",
          original_title: "Old Title"
        )

        product_data = {
          platform: "taobao",
          source_id: "123456789",
          title: "Updated Title",
          price: 199.99,
          currency: "CNY",
          url: "https://item.taobao.com/item.htm?id=123456789",
          description: "Updated description"
        }

        expect {
          post "/api/v1/products/extract",
            params: product_data,
            headers: auth_header,
            as: :json
        }.not_to change(SourceProduct, :count)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["title"]).to eq("Updated Title")
        expect(json["data"]["price"]).to eq(199.99)

        existing_product.reload
        expect(existing_product.original_title).to eq("Updated Title")
      end
    end

    context "with invalid data" do
      it "returns validation error for missing required fields" do
        post "/api/v1/products/extract",
          params: { platform: "taobao" },
          headers: auth_header,
          as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("VALIDATION_FAILED")
      end

      it "returns error for invalid platform" do
        post "/api/v1/products/extract",
          params: {
            platform: "invalid_platform",
            source_id: "123",
            title: "Test",
            price: 10,
            currency: "USD"
          },
          headers: auth_header,
          as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("INVALID_PLATFORM")
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/products/extract",
          params: { platform: "taobao" },
          as: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("AUTH_MISSING_TOKEN")
      end
    end
  end

  describe "GET /api/v1/source_products" do
    before do
      create_list(:source_product, 3, account: account, status: :ready)
      create_list(:source_product, 2, account: account, source_platform: :aliexpress, status: :pending)
      create(:source_product, account: create(:account)) # Different account
    end

    it "returns paginated list of products" do
      get "/api/v1/source_products", headers: auth_header

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["success"]).to be true
      expect(json["data"].length).to eq(5) # Only products from current account
      expect(json["meta"]).to be_present
      expect(json["meta"]["page"]).to eq(1)
      expect(json["meta"]["per_page"]).to eq(25)
    end

    it "filters by status" do
      get "/api/v1/source_products",
        params: { status: "ready" },
        headers: auth_header

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["data"].length).to eq(3)
      expect(json["data"].all? { |p| p["status"] == "ready" }).to be true
    end

    it "filters by platform" do
      get "/api/v1/source_products",
        params: { platform: "aliexpress" },
        headers: auth_header

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["data"].length).to eq(2)
      expect(json["data"].all? { |p| p["platform"] == "aliexpress" }).to be true
    end

    it "supports cursor-based pagination" do
      get "/api/v1/source_products",
        params: { per_page: 2 },
        headers: auth_header

      json = JSON.parse(response.body)
      first_page = json["data"]
      next_cursor = json["meta"]["next_cursor"]

      expect(first_page.length).to eq(2)
      expect(next_cursor).to be_present

      # Fetch next page
      get "/api/v1/source_products",
        params: { per_page: 2, cursor: next_cursor },
        headers: auth_header

      json = JSON.parse(response.body)
      second_page = json["data"]

      expect(second_page.length).to eq(2)
      expect(second_page).not_to eq(first_page)
    end
  end

  describe "GET /api/v1/source_products/:id" do
    let(:product) { create(:source_product, account: account) }

    it "returns product details" do
      get "/api/v1/source_products/#{product.id}", headers: auth_header

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["success"]).to be true
      expect(json["data"]["id"]).to eq(product.id)
      expect(json["data"]["title"]).to eq(product.original_title)
      expect(json["data"]["platform"]).to eq(product.source_platform.to_s)
    end

    it "returns error for product from different account" do
      other_product = create(:source_product, account: create(:account))

      get "/api/v1/source_products/#{other_product.id}", headers: auth_header

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/products/stats" do
    before do
      create_list(:source_product, 5, account: account, status: :pending)
      create_list(:source_product, 8, account: account, status: :ready)
      create(:source_product, account: account, status: :failed)
      create(:catalog_product, account: account, status: :listed)
      create(:source_product, account: account, source_platform: :taobao)
      create(:source_product, account: account, source_platform: :aliexpress)
    end

    it "returns product statistics" do
      get "/api/v1/products/stats", headers: auth_header

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["success"]).to be true
      expect(json["data"]["total"]).to eq(16) # 5 + 8 + 1 + 1 + 1
      expect(json["data"]["pending"]).to eq(5)
      expect(json["data"]["ready"]).to eq(10) # 8 + 1 + 1
      expect(json["data"]["failed"]).to eq(1)
      expect(json["data"]["listed"]).to eq(1)
      expect(json["data"]["by_platform"]).to be_present
    end
  end

  describe "DELETE /api/v1/source_products/:id" do
    let(:product) { create(:source_product, account: account) }

    it "deletes product" do
      product # Force eager evaluation
      initial_count = SourceProduct.where(account_id: account.id).count
      
      delete "/api/v1/source_products/#{product.id}", headers: auth_header
      
      final_count = SourceProduct.where(account_id: account.id).count
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      
      expect(json["success"]).to be true
      expect(json["data"]["deleted"]).to be true
      expect(final_count).to eq(initial_count - 1)
    end

    it "returns error for product from different account" do
      other_product = create(:source_product, account: create(:account))

      expect {
        delete "/api/v1/source_products/#{other_product.id}", headers: auth_header
      }.not_to change(SourceProduct, :count)

      expect(response).to have_http_status(:not_found)
    end
  end
end
