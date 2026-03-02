# frozen_string_literal: true

# Base marketplace adapter for publishing listings
# Provides common functionality for all marketplace adapters
module Marketplace
  class BaseAdapter
    class AdapterError < StandardError; end
    class AuthenticationError < AdapterError; end
    class RateLimitError < AdapterError; end
    class ValidationError < AdapterError; end

    # Default timeout settings for API requests (in seconds)
    DEFAULT_TIMEOUT = 30
    MAX_RETRIES = 3

    # Publish a marketplace listing
    #
    # @abstract
    # @param listing [MarketplaceListing] The listing to publish
    # @return [Hash] Result with success flag and marketplace_product_id
    # @raise [NotImplementedError] if subclass doesn't implement
    def publish(listing)
      raise NotImplementedError, "Subclasses must implement #publish"
    end

    # Update an existing listing
    #
    # @abstract
    # @param listing [MarketplaceListing] The listing to update
    # @return [Hash] Result with success flag
    def update(listing)
      raise NotImplementedError, "Subclasses must implement #update"
    end

    # Delete/pause a listing
    #
    # @abstract
    # @param listing [MarketplaceListing] The listing to delete
    # @return [Hash] Result with success flag
    def delete(listing)
      raise NotImplementedError, "Subclasses must implement #delete"
    end

    # Validate listing before publishing (dry-run)
    #
    # @abstract
    # @param listing [MarketplaceListing] The listing to validate
    # @return [Hash] Validation result with errors if any
    def validate(listing)
      raise NotImplementedError, "Subclasses must implement #validate"
    end

    # Sync order status from marketplace
    #
    # @abstract
    # @param order [Order] The order to sync
    # @return [Hash] Updated order data
    def sync_order(order)
      raise NotImplementedError, "Subclasses must implement #sync_order"
    end

    protected

    # Get marketplace API credentials for account
    #
    # @param account [Account] The account
    # @param provider [String] The marketplace provider name
    # @return [ApiCredential, nil]
    def get_api_credential(account, provider)
      account.api_credentials.find_by(provider:, is_active: true)
    rescue NoMethodError
      # Handle case where account might be nil or doesn't have api_credentials
      nil
    end

    # Format product data for marketplace API
    #
    # @param listing [MarketplaceListing] The listing
    # @return [Hash] Formatted product data
    def format_product_data(listing)
      catalog_product = listing.catalog_product

      {
        title: catalog_product.translated_title,
        description: catalog_product.translated_description,
        price: listing.listing_price_krw,
        images: catalog_product.processed_images.map { |img| img[:original_image_url] },
        category_id: listing.marketplace_category_id,
        stock_quantity: listing.stock_quantity || 10,
        variants: format_variants(catalog_product, listing),
        attributes: format_attributes(catalog_product)
      }
    end

    # Format product variants for marketplace API
    #
    # @param catalog_product [CatalogProduct] The catalog product
    # @param listing [MarketplaceListing] The marketplace listing
    # @return [Array<Hash>] Formatted variants
    def format_variants(catalog_product, listing)
      return [] unless catalog_product.variants.present?

      catalog_product.variants.map do |variant|
        {
          name: variant[:name] || "기본 옵션",
          sku: variant[:sku] || "SKU-#{SecureRandom.hex(4)}",
          price: calculate_variant_price(listing.listing_price_krw, variant[:price_modifier]),
          stock: variant[:available] ? (listing.stock_quantity || 10) : 0,
          attributes: variant[:attributes] || {}
        }
      end
    end

    # Format product attributes for marketplace API
    #
    # @param catalog_product [CatalogProduct] The catalog product
    # @return [Hash] Product attributes
    def format_attributes(catalog_product)
      attributes = {}

      if catalog_product.specifications.present?
        catalog_product.specifications.each do |spec|
          attributes[spec[:name]] = spec[:value] if spec[:name] && spec[:value]
        end
      end

      attributes
    end

    # Calculate variant price with markup
    #
    # @param base_price [Integer] Base price in KRW
    # @param price_modifier [Float] Price modifier (e.g., 1.1 for 10% markup)
    # @return [Integer] Calculated variant price
    def calculate_variant_price(base_price, price_modifier = 1.0)
      (base_price * (price_modifier || 1.0)).to_i
    end

    # Log adapter error with context
    #
    # @param message [String] Error message
    # @param context [Hash] Additional context for debugging
    def log_error(message, context = {})
      full_message = "[#{self.class.name}] #{message}"
      Rails.logger.error(full_message)
      Rails.logger.error("Context: #{context.inspect}") if context.any?

      # Create audit log if account is available in context
      if context[:account]
        AuditLog.create(
          account: context[:account],
          action_type: 'error',
          entity_type: 'MarketplaceListing',
          entity_id: context[:listing_id],
          details: context.merge(message:)
        )
      end
    end

    # Handle API response with retry logic
    #
    # @param response [HTTPX::Response] The API response
    # @param listing [MarketplaceListing] The listing context
    # @param request_context [Hash] Request context for logging
    # @return [Hash] Parsed response or error
    def handle_response(response, listing, request_context = {})
      status = response.status.to_i

      case status
      when 200..299
        {
          success: true,
          data: parse_response_body(response)
        }
      when 401, 403
        log_error("Authentication failed: #{response.body}", { account: listing.account, listing_id: listing.id, **request_context })
        {
          success: false,
          error: '인증 실패: API 자격 증명을 확인해주세요.',
          error_type: :authentication
        }
      when 429
        log_error("Rate limit exceeded: #{response.body}", { account: listing.account, listing_id: listing.id, **request_context })
        {
          success: false,
          error: '요청 제한 초과: 잠시 후 다시 시도해주세요.',
          error_type: :rate_limit
        }
      when 400..499
        error_detail = parse_error_from_response(response)
        log_error("Client error (#{status}): #{error_detail}", { account: listing.account, listing_id: listing.id, **request_context })
        {
          success: false,
          error: "요청 오류 (#{status}): #{error_detail}",
          error_type: :client_error
        }
      when 500..599
        log_error("Server error (#{status}): #{response.body}", { account: listing.account, listing_id: listing.id, **request_context })
        {
          success: false,
          error: "서버 오류 (#{status}): 잠시 후 다시 시도해주세요.",
          error_type: :server_error
        }
      else
        log_error("Unknown response status: #{status}", { account: listing.account, listing_id: listing.id, **request_context })
        {
          success: false,
          error: "알 수 없는 오류가 발생했습니다.",
          error_type: :unknown
        }
      end
    end

    # Parse response body based on content type
    #
    # @param response [HTTPX::Response] The API response
    # @return [Hash, nil] Parsed JSON body or nil
    def parse_response_body(response)
      content_type = response.headers['content-type']&.split(';')&.first

      if content_type&.include?('application/json')
        JSON.parse(response.body) rescue {}
      else
        { raw_body: response.body }
      end
    end

    # Parse error message from API response
    #
    # @param response [HTTPX::Response] The API response
    # @return [String] Error message
    def parse_error_from_response(response)
      begin
        body = parse_response_body(response)

        # Try to extract error message from common response formats
        error_message =
          body['error'] ||
          body['error_description'] ||
          body['message'] ||
          body['errors']&.first&.dig('message') ||
          body.dig('response', 'error', 'message') ||
          response.body.to_s[0..200] # Fallback to first 200 chars

        error_message || '알 수 없는 오류'
      rescue JSON::ParserError
        response.body.to_s[0..200]
      end
    end

    # Execute request with retry logic
    #
    # @yield Block that makes the HTTP request
    # @return [HTTPX::Response] The successful response
    def execute_with_retry
      retries = 0
      last_exception = nil

      begin
        yield
      rescue HTTPX::TimeoutError => e
        retries += 1
        last_exception = e
        if retries < MAX_RETRIES
          sleep(2 ** retries) # Exponential backoff
          retry
        else
          raise AdapterError, "Request timed out after #{MAX_RETRIES} retries"
        end
      rescue HTTPX::ConnectionError => e
        retries += 1
        last_exception = e
        if retries < MAX_RETRIES
          sleep(2 ** retries)
          retry
        else
          raise AdapterError, "Connection failed after #{MAX_RETRIES} retries"
        end
      end
    end

    # Create audit log for marketplace action
    #
    # @param listing [MarketplaceListing] The listing
    # @param action_type [String] Type of action (publish, update, delete, etc.)
    # @param details [Hash] Additional details
    def create_audit_log(listing, action_type, details = {})
      AuditLog.create(
        account: listing.account,
        action_type:,
        entity_type: 'MarketplaceListing',
        entity_id: listing.id,
        details: {
          marketplace: listing.marketplace,
          catalog_product_id: listing.catalog_product_id,
          **details
        }
      )
    end
  end

  # Instantiate appropriate adapter based on marketplace
  #
  # @param marketplace [String] Marketplace name (smart_store, coupang, gmarket, elevenst)
  # @return [BaseAdapter] Adapter instance or nil if not found
  def self.instantiate(marketplace)
    case marketplace&.to_s
    when 'smart_store'
      SmartStoreAdapter.new
    when 'coupang'
      CoupangAdapter.new
    when 'gmarket'
      GmarketAdapter.new
    when 'elevenst'
      ElevenstAdapter.new
    else
      nil
    end
  end
end
