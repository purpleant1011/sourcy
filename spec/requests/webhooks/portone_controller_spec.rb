# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Webhooks::PortoneController", type: :request do
  let(:account) { create(:account) }
  let(:portone_secret) { "test_portone_secret_key_klmno" }
  let(:external_event_id) { "portone_event_#{SecureRandom.hex(8)}" }

  let(:webhook_payload) do
    {
      external_event_id: external_event_id,
      event_type: "payment.created",
      order_id: "PO#{SecureRandom.hex(6).upcase}",
      order_status: "paid"
    }.to_json
  end

  before do
    # Mock the webhook secret
    allow(Rails.application.credentials).to receive(:dig).with(:webhooks, :portone, :secret).and_return(portone_secret)
  end

  describe "POST /webhooks/portone" do
    context "with valid signature" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", portone_secret, webhook_payload) }

      it "creates webhook event and processes order status change" do
        # Create an existing order for the account
        existing_order = create(:order, account: account, external_order_id: "PO#{SecureRandom.hex(6).upcase}", order_status: :pending, marketplace_platform: :portone)

        # Update payload to match existing order
        payload_with_order = {
          external_event_id: external_event_id,
          event_type: "payment.succeeded",
          order_id: existing_order.external_order_id,
          order_status: "shipped"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", portone_secret, payload_with_order)

        post "/webhooks/portone",
             params: payload_with_order,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["processed"]).to be true
        expect(json["data"]["event_id"]).to be_present

        # Verify webhook event was created
        event = WebhookEvent.find_by(external_event_id: external_event_id, provider: :portone)
        expect(event).to be_present
        expect(event.status).to eq("processed")
        expect(event.account_id).to eq(account.id)

        # Verify order status was updated
        existing_order.reload
        expect(existing_order.order_status).to eq("shipped")
      end

      it "creates webhook event without order" do
        post "/webhooks/portone",
             params: webhook_payload,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["processed"]).to be true

        # Verify webhook event was created
        event = WebhookEvent.find_by(external_event_id: external_event_id, provider: :portone)
        expect(event).to be_present
        expect(event.status).to eq("processed")
      end

      it "handles duplicate events" do
        # Create the webhook event first (processed)
        existing_event = create(:webhook_event,
                                account: account,
                                provider: :portone,
                                external_event_id: external_event_id,
                                status: :processed,
                                processed_at: 1.hour.ago)

        post "/webhooks/portone",
             params: webhook_payload,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["data"]["duplicated"]).to be true
        expect(json["data"]["event_id"]).to eq(existing_event.id)

        # Verify no new event was created
        expect(WebhookEvent.where(external_event_id: external_event_id, provider: :portone).count).to eq(1)
      end
    end

    context "with invalid signature" do
      it "returns unauthorized" do
        post "/webhooks/portone",
             params: webhook_payload,
             headers: {
               "X-Portone-Signature" => "invalid_signature",
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("WEBHOOK_SIGNATURE_INVALID")
      end

      it "returns unauthorized without signature header" do
        post "/webhooks/portone",
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
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", portone_secret, webhook_payload) }

      it "returns error without account" do
        post "/webhooks/portone",
             params: webhook_payload,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]["code"]).to eq("WEBHOOK_ACCOUNT_NOT_FOUND")
      end

      it "returns error with invalid account id" do
        post "/webhooks/portone",
             params: webhook_payload,
             headers: {
               "X-Portone-Signature" => signature,
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
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", portone_secret, webhook_payload) }

      it "identifies account by slug header" do
        post "/webhooks/portone",
             params: webhook_payload,
             headers: {
               "X-Portone-Signature" => signature,
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
          event_type: "payment.created",
          account_slug: account.slug,
          order_status: "paid"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", portone_secret, payload_with_slug)

        post "/webhooks/portone",
             params: payload_with_slug,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json"
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
      end
    end

    context "order status mapping" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", portone_secret, webhook_payload) }

      it "maps various order statuses correctly" do
        existing_order = create(:order, account: account, external_order_id: "PO#{SecureRandom.hex(6).upcase}", order_status: :pending, marketplace_platform: :portone)

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
            external_event_id: "portone_test_#{input_status}_#{SecureRandom.hex(4)}",
            event_type: "payment.status_changed",
            order_id: existing_order.external_order_id,
            order_status: input_status
          }.to_json
          sig = OpenSSL::HMAC.hexdigest("SHA256", portone_secret, payload)

          post "/webhooks/portone",
               params: payload,
               headers: {
                 "X-Portone-Signature" => sig,
                 "Content-Type" => "application/json",
                 "X-Account-Id" => account.id
               }

          expect(response).to have_http_status(:ok)
          existing_order.reload
          expect(existing_order.order_status).to eq(expected_status.to_s)
        end
      end
    end

    context "payment webhook scenarios" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", portone_secret, webhook_payload) }

      it "handles payment succeeded event" do
        existing_order = create(:order, account: account, external_order_id: "PO#{SecureRandom.hex(6).upcase}", order_status: :pending, marketplace_platform: :portone)

        payload_payment = {
          external_event_id: "payment_event_#{SecureRandom.hex(8)}",
          event_type: "payment.succeeded",
          order_id: existing_order.external_order_id,
          order_status: "paid"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", portone_secret, payload_payment)

        post "/webhooks/portone",
             params: payload_payment,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        existing_order.reload
        expect(existing_order.order_status).to eq("paid")
      end

      it "handles payment failed event" do
        existing_order = create(:order, account: account, external_order_id: "PO#{SecureRandom.hex(6).upcase}", order_status: :pending, marketplace_platform: :portone)

        payload_payment_failed = {
          external_event_id: "payment_failed_#{SecureRandom.hex(8)}",
          event_type: "payment.failed",
          order_id: existing_order.external_order_id,
          order_status: "canceled"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", portone_secret, payload_payment_failed)

        post "/webhooks/portone",
             params: payload_payment_failed,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        existing_order.reload
        expect(existing_order.order_status).to eq("canceled")
      end
    end

    context "event ID variations" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", portone_secret, webhook_payload) }

      it "extracts event_id from id field" do
        event_id = "portone_id_#{SecureRandom.hex(8)}"
        payload_with_id = {
          id: event_id,
          event_type: "payment.created"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", portone_secret, payload_with_id)

        post "/webhooks/portone",
             params: payload_with_id,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event = WebhookEvent.find_by(external_event_id: event_id, provider: :portone)
        expect(event).to be_present
        payload_with_id = {
          id: "portone_id_#{SecureRandom.hex(8)}",
          event_type: "payment.created"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", portone_secret, payload_with_id)

        post "/webhooks/portone",
             params: payload_with_id,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        event = WebhookEvent.find_by(external_event_id: event_id, provider: :portone)
        expect(event).to be_present
      end
    end

    context "external order ID extraction" do
      let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", portone_secret, webhook_payload) }

      it "extracts external_order_id from payload" do
        payload_with_external_order = {
          external_event_id: "test_event_#{SecureRandom.hex(8)}",
          event_type: "payment.created",
          external_order_id: "PO_ORDER_12345",
          order_status: "pending"
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", portone_secret, payload_with_external_order)

        post "/webhooks/portone",
             params: payload_with_external_order,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
      end

      it "extracts external_order_id from nested order object" do
        existing_order = create(:order, account: account, external_order_id: "PO_ORDER_67890", order_status: :pending, marketplace_platform: :portone)

        payload_with_nested = {
          external_event_id: "test_event_nested_#{SecureRandom.hex(8)}",
          event_type: "payment.status_changed",
          order: {
            id: existing_order.external_order_id,
            status: "delivered"
          }
        }.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", portone_secret, payload_with_nested)

        post "/webhooks/portone",
             params: payload_with_nested,
             headers: {
               "X-Portone-Signature" => signature,
               "Content-Type" => "application/json",
               "X-Account-Id" => account.id
             }

        expect(response).to have_http_status(:ok)
        existing_order.reload
        expect(existing_order.order_status).to eq("delivered")
      end
    end
  end
end
