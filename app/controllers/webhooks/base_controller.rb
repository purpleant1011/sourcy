# frozen_string_literal: true

require "json"

module Webhooks
  class BaseController < ActionController::API
    before_action :parse_payload
    before_action :set_account
    before_action :verify_webhook_signature!

    rescue_from ActiveRecord::RecordInvalid, with: :render_invalid_record
    rescue_from ActionDispatch::Http::Parameters::ParseError, JSON::ParserError, with: :handle_json_error

    def handle_json_error(error)
      @payload = {}
      @error_handled = true
      # Continue processing with empty payload
    end

    def create
      external_event_id = extract_external_event_id
      event_type = extract_event_type
      event = find_or_create_webhook_event!(external_event_id: external_event_id, event_type: event_type)

      if event.processed_at.present?
        return render json: { success: true, data: { duplicated: true, event_id: event.id } }, status: :ok
      end

      process_order_status_change!
      event.update!(status: :processed, processed_at: Time.current)

      render json: { success: true, data: { processed: true, event_id: event.id } }, status: :ok
    rescue StandardError => error
      event&.update(status: :failed, error_message: error.message)
      render json: {
        success: false,
        error: {
          code: "WEBHOOK_PROCESSING_FAILED",
          message: "Webhook processing failed",
          details: { provider: provider_key, reason: error.message }
        }
      }, status: :unprocessable_entity
    end

    private

    attr_reader :payload, :account

    def provider_key
      raise NotImplementedError, "provider_key must be implemented"
    end

    def verify_webhook_signature!
      raise NotImplementedError, "verify_webhook_signature! must be implemented"
    end
    #
    # Verify webhook IP allowlist
    # PRD 섹션 6: IP 허용 목록 검증
    def verify_webhook_ip_allowlist!
      return if ip_allowlist.blank?
      return if ip_allowlist.include?(request.remote_ip)

      render json: {
        success: false,
        error: {
          code: "WEBHOOK_IP_NOT_ALLOWED",
          message: "IP address is not in allowlist",
          details: { provider: provider_key, ip: request.remote_ip }
        }
      }, status: :forbidden
    end

    # Get IP allowlist from credentials
    # PRD 섹션 6: 각 마켓플레이스별 IP 허용 목록
    def ip_allowlist
      @ip_allowlist ||= begin
        allowlist = Rails.application.credentials.dig(:webhooks, provider_key.to_s, :ip_allowlist)
        return [] if allowlist.blank?

        allowlist = [allowlist] unless allowlist.is_a?(Array)
        allowlist.map { |ip| IPAddr.new(ip) }
      rescue IPAddr::InvalidAddressError => e
        Rails.logger.warn("Invalid IP address in webhook allowlist for #{provider_key}: #{e.message}")
        []
      rescue NoMethodError
        # Credentials not found, allow all IPs for backward compatibility
        Rails.logger.warn("Webhook IP allowlist not configured for #{provider_key}, allowing all IPs")
        []
    end

    def verify_hmac_signature!(header:, credentials_key:)
      provided = request.headers[header].to_s
      secret = Rails.application.credentials.dig(:webhooks, credentials_key, :secret).to_s
      secret = Rails.application.secret_key_base if secret.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)
      return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

      render json: {
        success: false,
        error: {
          code: "WEBHOOK_SIGNATURE_INVALID",
          message: "Invalid webhook signature",
          details: { provider: provider_key }
        }
      }, status: :unauthorized
    end

    def parse_payload
      @payload = request.request_parameters.presence || JSON.parse(request.raw_post.presence || "{}")
    rescue JSON::ParserError
      @payload = {}
    end

    def set_account
      account_id = request.headers["X-Account-Id"].presence || payload["account_id"].presence
      account_slug = request.headers["X-Account-Slug"].presence || payload["account_slug"].presence

      @account = if account_id.present?
        Account.find_by(id: account_id)
      elsif account_slug.present?
        Account.find_by(slug: account_slug)
      end

      return if @account.present?

      render json: {
        success: false,
        error: {
          code: "WEBHOOK_ACCOUNT_NOT_FOUND",
          message: "Account context is missing",
          details: {}
        }
      }, status: :unprocessable_entity
    end

    def extract_external_event_id
      payload["external_event_id"] || payload["event_id"] || payload["id"] || request.headers["X-Event-Id"] || SecureRandom.uuid
    end

    def extract_event_type
      payload["event_type"] || payload["type"] || payload.dig("event", "type") || "unknown"
    end

    def find_or_create_webhook_event!(external_event_id:, event_type:)
      existing = WebhookEvent.find_by(account_id: account.id, provider: provider_store_value, external_event_id: external_event_id)
      return existing if existing.present?

      if provider_store_value == 4
        WebhookEvent.insert(
          {
            account_id: account.id,
            provider: provider_store_value,
            external_event_id: external_event_id,
            event_type: event_type,
            payload: payload,
            status: 0,
            created_at: Time.current,
            updated_at: Time.current
          }
        )
        WebhookEvent.find_by!(account_id: account.id, provider: provider_store_value, external_event_id: external_event_id)
      else
        Current.account = account
        WebhookEvent.create!(
          account: account,
          provider: provider_store_value,
          external_event_id: external_event_id,
          event_type: event_type,
          payload: payload,
          status: :pending
        )
      end
    end

    def provider_store_value
      return 4 if provider_key.to_sym == :gmarket

      provider_key
    end

    def process_order_status_change!
      external_order_id = payload["order_id"] || payload["external_order_id"] || payload.dig("order", "id")
      return if external_order_id.blank?

      order = account.orders.find_by(external_order_id: external_order_id)
      return if order.blank?

      incoming_status = payload["order_status"] || payload["status"] || payload.dig("order", "status")
      mapped_status = map_order_status(incoming_status)
      order.update!(order_status: mapped_status) if mapped_status.present?
    end

    def map_order_status(incoming_status)
      return if incoming_status.blank?

      normalized = incoming_status.to_s.downcase
      return :pending if normalized.include?("pending")
      return :paid if normalized.include?("paid")
      return :preparing if normalized.include?("prepare") || normalized.include?("preparing")
      return :shipped if normalized.include?("ship") || normalized.include?("shipping")
      return :delivered if normalized.include?("deliver") || normalized.include?("delivery")
      return :canceled if normalized.include?("cancel") || normalized.include?("cancellation")
      return :returned if normalized.include?("return") || normalized.include?("refund")

      nil
    end

    def render_bad_request(error)
      render json: {
        success: false,
        error: {
          code: "INVALID_REQUEST",
          message: error.message,
          details: {}
        }
      }, status: :bad_request
    end

    def render_invalid_record(error)
      render json: {
        success: false,
        error: {
          code: "VALIDATION_FAILED",
          message: "Validation failed",
          details: error.record.errors.to_hash
        }
      }, status: :unprocessable_entity
    end
  end
end
