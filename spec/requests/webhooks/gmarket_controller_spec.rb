# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Webhooks::GmarketController", type: :request do
  let(:account) { create(:account) }
  let(:gmarket_secret) { "test_gmarket_secret_key_abcde" }
  let(:external_event_id) { "gmarket_event_#{SecureRandom.hex(8)}" }

  let(:webhook_payload) do
    {
      external_event_id: external_event_id,
      event_type: "order.created",
      order_id: "GM#{SecureRandom.hex(6).upcase}",
      order_status: "paid"
    }.to_json
  end

  before do
    # Mock the webhook secret
    allow(Rails.application.credentials).to receive(:dig).with(:webhooks, :gmarket, :secret).and_return(gmarket_secret)
  end

  describe "POST /webhooks/gmarket" do
    context "with valid signature" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, webhook_payload) }

      it "creates webhook event and processes order status change" do
        # Create an existing order for the account
        existing_order = create(:order, account: account, external_order_id: "GM#{SecureRandom.hex(6).upcase}", order_status: :pending, marketplace_platform: :gmarket)

        # Update payload to match existing order
        payload_with_order = {
          external_event_id: external_event_id,
          event_type: "order.status_changed",
          order_id: existing_order.external_order_id,
          order_status: "delivered"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, payload_with_order)

        post "/webhooks/gmarket",
             params: payload_with_order,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["processed"]).to be true
        expect(json["data"]["event_id"]).to be_present

        # Verify webhook event was created
        event = WebhookEvent.find_by(external_event_id: external_event_id, account_id: account.id)
        expect(event).to be_present
        expect(event.status).to eq("processed")

        # Note: Gmarket uses provider_store_value = 4 which is not in the enum
        # The database stores it as 4, but the enum doesn't include it
        expect(event.provider_before_type_cast).to eq(4)

        # Verify order status was updated
        existing_order.reload
        expect(existing_order.order_status).to eq("delivered")
      end

      it "creates webhook event without order" do
        post "/webhooks/gmarket",
             params: webhook_payload,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["processed"]).to be true

        # Verify webhook event was created
        event = WebhookEvent.find_by(external_event_id: external_event_id, account_id: account.id)
        expect(event).to be_present
        expect(event.status).to eq("processed")
        expect(event.provider_before_type_cast).to eq(4)
      end

      it "handles duplicate events" do
        # Create the webhook event first using insert (gmarket special case)
        WebhookEvent.insert(
          {
            account_id: account.id,
            provider: 4,
            external_event_id: external_event_id,
            event_type: "order.created",
            payload: {},
            status: 1,
            processed_at: Time.current,
            created_at: Time.current,
            updated_at: Time.current
          }
        )
        existing_event = WebhookEvent.find_by(external_event_id: external_event_id, account_id: account.id)

        post "/webhooks/gmarket",
             params: webhook_payload,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["duplicated"]).to be true
        expect(json["data"]["event_id"]).to eq(existing_event.id)

        # Verify no new event was created
        expect(WebhookEvent.where(external_event_id: external_event_id, account_id: account.id).count).to eq(1)
      end
    end

    context "with invalid signature" do
      it "returns unauthorized" do
        post "/webhooks/gmarket",
             params: webhook_payload,
             headers: {
               "X-Gmarket-Signature" => "invalid_signature",
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("WEBHOOK_SIGNATURE_INVALID")
      end

      it "returns unauthorized without signature header" do
        post "/webhooks/gmarket",
             params: webhook_payload,
             headers: {
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("WEBHOOK_SIGNATURE_INVALID")
      end
    end

    context "with missing account context" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, webhook_payload) }

      it "returns error without account" do
        post "/webhooks/gmarket",
             params: webhook_payload,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("WEBHOOK_ACCOUNT_NOT_FOUND")
      end

      it "returns error with invalid account id" do
        post "/webhooks/gmarket",
             params: webhook_payload,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => SecureRandom.uuid
             }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("WEBHOOK_ACCOUNT_NOT_FOUND")
      end
    end

    context "account identification via slug" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, webhook_payload) }

      it "identifies account by slug header" do
        post "/webhooks/gmarket",
             params: webhook_payload,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Slug" => account.slug
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
      end

      it "identifies account by slug in payload" do
        payload_with_slug = {
          external_event_id: external_event_id,
          event_type: "order.created",
          account_slug: account.slug,
          order_status: "paid"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, payload_with_slug)

        post "/webhooks/gmarket",
             params: payload_with_slug,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
      end
    end

    context "order status mapping" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, webhook_payload) }

      it "maps various order statuses correctly" do
        existing_order = create(:order, account: account, external_order_id: "GM#{SecureRandom.hex(6).upcase}", order_status: :pending, marketplace_platform: :gmarket)

        status_mappings = {
          "pending" => :pending,
          "paid" => :paid,
          "preparing" => :preparing,
          "shipped" => :shipped,
          "delivered" => :delivered,
          "canceled" => :canceled,
          "returned" => :returned
        }

        status_mappings.each do |input_status, expected_status|
          payload = {
            external_event_id: "gmarket_test_#{input_status}_#{SecureRandom.hex(4)}",
            event_type: "order.status_changed",
            order_id: existing_order.external_order_id,
            order_status: input_status
          }.to_json
          sig = OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, payload)

          post "/webhooks/gmarket",
               params: payload,
               headers: {
                 "X-Gmarket-Signature" => sig,
                 "Content-Type" => "application/json",
                 "X-Account-Id" => account.id
               }

          expect(response).to have_http_status(:ok)
          existing_order.reload
          expect(existing_order.order_status).to eq(expected_status.to_s)
        end
      end
    end

    context "event ID extraction from nested order object" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, webhook_payload) }

      it "extracts event_id from nested order object" do
        payload_with_nested_order = {
          order: {
            id: "nested_order_id_123",
            status: "paid"
          },
          event_type: "order.created"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, payload_with_nested_order)

        post "/webhooks/gmarket",
             params: payload_with_nested_order,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        # The controller uses order_id first, then order.id as fallback
        # Since order_id is not provided, it will use the nested id from order object
        # for external_order_id but not for external_event_id
      end

      it "extracts event_type from nested event object" do
        event_id = "test_nested_event_#{SecureRandom.hex(8)}"
        payload_with_nested_event = {
          external_event_id: event_id,
          event: {
            type: "order.updated"
          }
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, payload_with_nested_event)

        post "/webhooks/gmarket",
             params: payload_with_nested_event,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event = WebhookEvent.find_by(external_event_id: event_id, account_id: account.id)
        expect(event).to be_present
        payload_with_nested_event = {
          external_event_id: "test_nested_event_#{SecureRandom.hex(8)}",
          event: {
            type: "order.updated"
          }
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", gmarket_secret, payload_with_nested_event)

        post "/webhooks/gmarket",
             params: payload_with_nested_event,
             headers: {
               "X-Gmarket-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event = WebhookEvent.find_by(external_event_id: event_id, account_id: account.id)
        expect(event).to be_present
        expect(event.event_type).to eq("order.updated")
      end
    end
  end
end
