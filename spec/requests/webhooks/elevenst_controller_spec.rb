# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Webhooks::ElevenstController", type: :request do
  let(:account) { create(:account) }
  let(:elevenst_secret) { "test_elevenst_secret_fghij" }
  let(:external_event_id) { "elevenst_event_#{SecureRandom.hex(8)}" }

  let(:webhook_payload) do
    {
      external_event_id: external_event_id,
      event_type: "order.status_changed",
      order_id: "11ST#{SecureRandom.hex(6).upcase}",
      order_status: "paid"
    }.to_json
  end

  before do
    # Mock the webhook secret
    allow(Rails.application.credentials).to receive(:dig).with(:webhooks, :eleven_street, :secret).and_return(elevenst_secret)
  end

  describe "POST /webhooks/elevenst" do
    context "with valid signature" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, webhook_payload) }

      it "creates webhook event and processes order status change" do
        # Create an existing order for the account
        existing_order = create(:order, account: account, external_order_id: "11ST#{SecureRandom.hex(6).upcase}", order_status: :pending, marketplace_platform: :eleven_street)

        # Update payload to match existing order
        payload_with_order = {
          external_event_id: external_event_id,
          event_type: "order.status_changed",
          order_id: existing_order.external_order_id,
          order_status: "shipped"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, payload_with_order)

        post "/webhooks/elevenst",
             params: payload_with_order,
             headers: {
               "X-11st-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["processed"]).to be true
        expect(json["data"]["event_id"]).to be_present

        # Verify webhook event was created
        event = WebhookEvent.find_by(external_event_id: external_event_id, provider: :eleven_street)
        expect(event).to be_present
        expect(event.status).to eq("processed")
        expect(event.account_id).to eq(account.id)
        expect(event.event_type).to eq("order.status_changed")

        # Verify order status was updated
        existing_order.reload
        expect(existing_order.order_status).to eq("shipped")
      end

      it "creates webhook event without order" do
        post "/webhooks/elevenst",
             params: webhook_payload,
             headers: {
               "X-11st-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["processed"]).to be true

        # Verify webhook event was created even without order
        event = WebhookEvent.find_by(external_event_id: external_event_id, provider: :eleven_street)
        expect(event).to be_present
      end
    end

    context "with invalid signature" do
      it "returns unauthorized" do
        post "/webhooks/elevenst",
             params: webhook_payload,
             headers: {
               "X-11st-Signature" => "invalid_signature",
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
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, webhook_payload) }

      it "identifies account by ID header" do
        post "/webhooks/elevenst",
             params: webhook_payload,
             headers: {
               "X-11st-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
      end

      it "identifies account by slug header" do
        post "/webhooks/elevenst",
             params: webhook_payload,
             headers: {
               "X-11st-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Slug" => account.slug
             }

        expect(response).to have_http_status(:ok)
      end

      it "identifies account by slug in payload" do
        payload_with_slug = JSON.parse(webhook_payload).merge(account_slug: account.slug).to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, payload_with_slug)

        post "/webhooks/elevenst",
             params: payload_with_slug,
             headers: {
               "X-11st-Signature" => signature,
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
      end
    end

    context "duplicate event handling" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, webhook_payload) }

      it "processes duplicate event only once" do
        # First request
        post "/webhooks/elevenst",
             params: webhook_payload,
             headers: {
               "X-11st-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event_count = WebhookEvent.where(external_event_id: external_event_id, provider: :eleven_street).count
        expect(event_count).to eq(1)

        # Second request (duplicate)
        post "/webhooks/elevenst",
             params: webhook_payload,
             headers: {
               "X-11st-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["data"]["duplicated"]).to be true

        # Event count should still be 1
        event_count = WebhookEvent.where(external_event_id: external_event_id, provider: :eleven_street).count
        expect(event_count).to eq(1)
      end
    end

    context "external order ID extraction" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, webhook_payload) }

      it "extracts external_order_id from nested order object" do
        existing_order = create(:order, account: account, external_order_id: "11ST_ORDER_67890", order_status: :pending, marketplace_platform: :eleven_street)

        payload_with_nested_order = {
          external_event_id: external_event_id,
          event_type: "order.status_changed",
          order: {
            id: existing_order.external_order_id,
            status: "shipped"
          }
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, payload_with_nested_order)

        post "/webhooks/elevenst",
             params: payload_with_nested_order,
             headers: {
               "X-11st-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        existing_order.reload
        expect(existing_order.order_status).to eq("shipped")
      end
    end

    context "order status mapping" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, webhook_payload) }

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
          existing_order = create(:order, account: account, external_order_id: "11ST#{SecureRandom.hex(6).upcase}", order_status: :pending, marketplace_platform: :eleven_street)

          payload_with_status = {
            external_event_id: "elevenst_status_test_#{SecureRandom.hex(8)}",
            event_type: "order.status_changed",
            order_id: existing_order.external_order_id,
            order_status: incoming_status
          }.to_json
          signature = OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, payload_with_status)

          post "/webhooks/elevenst",
               params: payload_with_status,
               headers: {
                 "X-11st-Signature" => signature,
                 "Content-Type" => "application/json",
                 "X-Account-Id" => account.id
               }

          expect(response).to have_http_status(:ok)
          existing_order.reload
          expect(existing_order.order_status).to eq(expected_status.to_s)
        end
      end
    end

    context "event type extraction variations" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, webhook_payload) }

      it "extracts event_type from event.type field" do
        event_id = "test_event_#{SecureRandom.hex(8)}"
        payload_with_nested_event_type = {
          external_event_id: event_id,
          event: {
            type: "order.cancelled"
          }
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", elevenst_secret, payload_with_nested_event_type)

        post "/webhooks/elevenst",
             params: payload_with_nested_event_type,
             headers: {
               "X-11st-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event = WebhookEvent.find_by(external_event_id: event_id, provider: :eleven_street)
        expect(event).to be_present
        expect(event.event_type).to eq("order.cancelled")
      end
    end
  end
end
