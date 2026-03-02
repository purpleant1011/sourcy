# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Webhooks::CoupangController", type: :request do
  let(:account) { create(:account) }
  let(:coupang_secret) { "test_coupang_secret_abcde" }
  let(:external_event_id) { "coupang_event_#{SecureRandom.hex(8)}" }

  let(:webhook_payload) do
    {
      external_event_id: external_event_id,
      event_type: "order.status_changed",
      order_id: "CP#{SecureRandom.hex(6).upcase}",
      order_status: "paid"
    }.to_json
  end

  before do
    # Mock the webhook secret
    allow(Rails.application.credentials).to receive(:dig).with(:webhooks, :coupang, :secret).and_return(coupang_secret)
  end

  describe "POST /webhooks/coupang" do
    context "with valid signature" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, webhook_payload) }

      it "creates webhook event and processes order status change" do
        # Create an existing order for the account
        existing_order = create(:order, account: account, external_order_id: "CP#{SecureRandom.hex(6).upcase}", order_status: :paid, marketplace_platform: :coupang)

        # Update payload to match existing order
        payload_with_order = {
          external_event_id: external_event_id,
          event_type: "order.status_changed",
          order_id: existing_order.external_order_id,
          order_status: "shipped"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, payload_with_order)

        post "/webhooks/coupang",
             params: payload_with_order,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["processed"]).to be true
        expect(json["data"]["event_id"]).to be_present

        # Verify webhook event was created
        event = WebhookEvent.find_by(external_event_id: external_event_id, provider: :coupang)
        expect(event).to be_present
        expect(event.status).to eq("processed")
        expect(event.account_id).to eq(account.id)
        expect(event.event_type).to eq("order.status_changed")

        # Verify order status was updated
        existing_order.reload
        expect(existing_order.order_status).to eq("shipped")
      end

      it "creates webhook event without order" do
        post "/webhooks/coupang",
             params: webhook_payload,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["processed"]).to be true

        # Verify webhook event was created even without order
        event = WebhookEvent.find_by(external_event_id: external_event_id, provider: :coupang)
        expect(event).to be_present
      end
    end

    context "with invalid signature" do
      it "returns unauthorized" do
        post "/webhooks/coupang",
             params: webhook_payload,
             headers: {
               "X-Coupang-Signature" => "invalid_signature",
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("WEBHOOK_SIGNATURE_INVALID")
      end
    end

    context "account identification" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, webhook_payload) }

      it "identifies account by ID header" do
        post "/webhooks/coupang",
             params: webhook_payload,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
      end

      it "identifies account by slug header" do
        post "/webhooks/coupang",
             params: webhook_payload,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Slug" => account.slug
             }

        expect(response).to have_http_status(:ok)
      end

      it "identifies account by slug in payload" do
        payload_with_slug = JSON.parse(webhook_payload).merge(account_slug: account.slug).to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, payload_with_slug)

        post "/webhooks/coupang",
             params: payload_with_slug,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end
    end

    context "duplicate event handling" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, webhook_payload) }

      it "processes duplicate event only once" do
        # First request
        post "/webhooks/coupang",
             params: webhook_payload,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event_count = WebhookEvent.where(external_event_id: external_event_id, provider: :coupang).count
        expect(event_count).to eq(1)

        # Second request (duplicate)
        post "/webhooks/coupang",
             params: webhook_payload,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["data"]["duplicated"]).to be true

        # Event count should still be 1
        event_count = WebhookEvent.where(external_event_id: external_event_id, provider: :coupang).count
        expect(event_count).to eq(1)
      end
    end

    context "order status mapping" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, webhook_payload) }

      it "maps various order statuses correctly" do
        status_mappings = {
          "pending" => "pending",
          "paid" => "paid",
          "preparing" => "preparing",
          "shipped" => "shipped",
          "delivered" => "delivered",
          "canceled" => "canceled",
          "returned" => "returned"
        }

        status_mappings.each do |incoming_status, expected_status|
          existing_order = create(:order, account: account, external_order_id: "CP#{SecureRandom.hex(6).upcase}", order_status: :pending, marketplace_platform: :coupang)

          payload_with_status = {
            external_event_id: "coupang_status_test_#{SecureRandom.hex(8)}",
            event_type: "order.status_changed",
            order_id: existing_order.external_order_id,
            order_status: incoming_status
          }.to_json
          signature = OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, payload_with_status)

          post "/webhooks/coupang",
               params: payload_with_status,
               headers: {
                 "X-Coupang-Signature" => signature,
                 "Content-Type" => "application/json",
                 "X-Account-Id" => account.id
               }

          expect(response).to have_http_status(:ok)
          existing_order.reload
          expect(existing_order.order_status).to eq(expected_status.to_s)
        end
      end
    end

    context "event type extraction" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, webhook_payload) }

      it "extracts event_type from payload" do
        event_id = "test_event_#{SecureRandom.hex(8)}"
        payload_with_event_type = {
          external_event_id: event_id,
          event_type: "order.updated"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, payload_with_event_type)

        post "/webhooks/coupang",
             params: payload_with_event_type,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event = WebhookEvent.find_by(external_event_id: event_id, provider: :coupang)
        expect(event).to be_present
        expect(event.event_type).to eq("order.updated")
      end

      it "extracts event_type from type field" do
        event_id = "test_event_type_#{SecureRandom.hex(8)}"
        payload_with_type = {
          external_event_id: event_id,
          type: "order.acknowledged"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, payload_with_type)

        post "/webhooks/coupang",
             params: payload_with_type,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event = WebhookEvent.find_by(external_event_id: event_id, provider: :coupang)
        expect(event).to be_present
        expect(event.event_type).to eq("order.acknowledged")
      end
    end

    context "event ID extraction" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, webhook_payload) }

      it "extracts event_id from external_event_id field" do
        event_id = "custom_event_12345"
        payload_with_custom_event_id = {
          external_event_id: event_id,
          event_type: "order.created",
          order_id: "CP#{SecureRandom.hex(6).upcase}",
          order_status: "paid"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", coupang_secret, payload_with_custom_event_id)

        post "/webhooks/coupang",
             params: payload_with_custom_event_id,
             headers: {
               "X-Coupang-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event = WebhookEvent.find_by(external_event_id: event_id, provider: :coupang)
        expect(event).to be_present
      end
    end
  end
end
