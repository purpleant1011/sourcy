# frozen_string_literal: true

# Coupang adapter for publishing listings
# Official API: https://developers.coupang.com/docs
module Marketplace
  class CoupangAdapter < BaseAdapter
    # Coupang API endpoints
    BASE_URL = 'https://api-gateway.coupang.com'
    OAUTH_URL = 'https://api-gateway.coupang.com/login/oauth/token'

    # Publish a listing to Coupang
    #
    # @param listing [MarketplaceListing] The listing to publish
    # @return [Hash] Result with marketplace_product_id and marketplace_url
    def publish(listing)
      credential = get_api_credential(listing.account, 'coupang')
      return { success: false, error: 'Coupang API 자격 증명이 필요합니다.' } unless credential

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        product_data = format_coupang_product(listing)

        response = execute_with_retry do
          HTTPX.post(
            "#{BASE_URL}/v1/providers/openapi/products/products",
            headers: build_headers(access_token, credential.access_key),
            json: product_data,
            timeout: DEFAULT_TIMEOUT
          )
        end

        result = handle_response(response, listing, { action: 'publish' })

        if result[:success]
          product_id = result.dig(:data, 'sellerProductId')
          create_audit_log(listing, 'publish', {
            marketplace_product_id: product_id,
            status: 'published'
          })
          {
            success: true,
            marketplace_product_id: product_id,
            marketplace_url: "https://www.coupang.com/vp/products/#{product_id}"
          }
        else
          result
        end
      rescue AdapterError => e
        log_error(e.message, { account: listing.account, listing_id: listing.id })
        { success: false, error: e.message }
      rescue StandardError => e
        log_error("Unexpected error: #{e.message}", { account: listing.account, listing_id: listing.id, backtrace: e.backtrace[0..3] })
        { success: false, error: '예상치 못한 오류가 발생했습니다.' }
      end
    end

    # Update an existing listing
    #
    # @param listing [MarketplaceListing] The listing to update
    # @return [Hash] Result with success flag
    def update(listing)
      credential = get_api_credential(listing.account, 'coupang')
      return { success: false, error: 'Coupang API 자격 증명이 필요합니다.' } unless credential

      return { success: false, error: '마켓플레이스 제품 ID가 필요합니다.' } unless listing.marketplace_product_id

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        product_data = format_coupang_product(listing)

        response = execute_with_retry do
          HTTPX.put(
            "#{BASE_URL}/v1/providers/openapi/products/products/#{listing.marketplace_product_id}",
            headers: build_headers(access_token, credential.access_key),
            json: product_data,
            timeout: DEFAULT_TIMEOUT
          )
        end

        result = handle_response(response, listing, { action: 'update', marketplace_product_id: listing.marketplace_product_id })

        if result[:success]
          create_audit_log(listing, 'update', {
            marketplace_product_id: listing.marketplace_product_id,
            status: 'updated'
          })
          { success: true }
        else
          result
        end
      rescue StandardError => e
        log_error(e.message, { account: listing.account, listing_id: listing.id })
        { success: false, error: e.message }
      end
    end

    # Delete/pause a listing
    #
    # @param listing [MarketplaceListing] The listing to delete
    # @return [Hash] Result with success flag
    def delete(listing)
      credential = get_api_credential(listing.account, 'coupang')
      return { success: false, error: 'Coupang API 자격 증명이 필요합니다.' } unless credential

      return { success: false, error: '마켓플레이스 제품 ID가 필요합니다.' } unless listing.marketplace_product_id

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        response = execute_with_retry do
          HTTPX.put(
            "#{BASE_URL}/v1/providers/openapi/products/products/#{listing.marketplace_product_id}/saleStatus",
            headers: build_headers(access_token, credential.access_key),
            json: { saleStatus: 'PAUSED' },
            timeout: DEFAULT_TIMEOUT
          )
        end

        result = handle_response(response, listing, { action: 'delete', marketplace_product_id: listing.marketplace_product_id })

        if result[:success]
          create_audit_log(listing, 'delete', {
            marketplace_product_id: listing.marketplace_product_id,
            status: 'deleted'
          })
          { success: true }
        else
          result
        end
      rescue StandardError => e
        log_error(e.message, { account: listing.account, listing_id: listing.id })
        { success: false, error: e.message }
      end
    end

    # Validate listing before publishing (dry-run)
    #
    # @param listing [MarketplaceListing] The listing to validate
    # @return [Hash] Validation result with errors if any
    def validate(listing)
      errors = []
      warnings = []

      catalog_product = listing.catalog_product

      errors << '제목이 필요합니다.' if catalog_product.translated_title.blank?
      errors << '가격이 필요합니다.' if listing.listing_price_krw.zero?
      errors << '카테고리가 필요합니다.' if listing.marketplace_category_id.blank?
      errors << '상품 이미지가 필요합니다.' if catalog_product.processed_images.empty?

      # Coupang specific validation
      if catalog_product.translated_title && catalog_product.translated_title.length > 80
        warnings << '제목이 너무 길 수 있습니다 (권장 80자 이내).'
      end

      if catalog_product.translated_description && catalog_product.translated_description.length > 2000
        errors << '상세 설명이 너무 깁니다 (최대 2000자).'
      end

      unless listing.brand_name.present?
        warnings << '브랜드명이 설정되지 않았습니다.'
      end

      {
        valid: errors.empty?,
        errors:,
        warnings:
      }
    end

    # Sync order status from Coupang
    #
    # @param order [Order] The order to sync
    # @return [Hash] Updated order data
    def sync_order(order)
      credential = get_api_credential(order.account, 'coupang')
      return { success: false, error: 'Coupang API 자격 증명이 필요합니다.' } unless credential

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        response = execute_with_retry do
          HTTPX.get(
            "#{BASE_URL}/v1/providers/openapi/shipping/orders/purchase-orders/#{order.marketplace_order_id}",
            headers: build_headers(access_token, credential.access_key),
            timeout: DEFAULT_TIMEOUT
          )
        end

        result = handle_response(response, nil, { action: 'sync_order', order_id: order.id })

        if result[:success]
          order_data = result[:data]
          {
            success: true,
            status: map_order_status(order_data.dig('purchaseOrderStatus')),
            updated_at: order_data.dig('lastModifiedDate')
          }
        else
          result
        end
      rescue StandardError => e
        log_error(e.message, { account: order.account, order_id: order.id })
        { success: false, error: e.message }
      end
    end

    private

    # Get OAuth2 access token
    #
    # @param credential [ApiCredential] The API credential
    # @return [String, nil] Access token or nil if failed
    def get_access_token(credential)
      response = HTTPX.post(
        OAUTH_URL,
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        body: URI.encode_www_form({
          grant_type: 'client_credentials',
          client_id: credential.access_key,
          client_secret: credential.secret_key
        }),
        timeout: DEFAULT_TIMEOUT
      )

      return nil unless response.status == 200

      body = JSON.parse(response.body) rescue nil
      body&.dig('access_token')
    rescue StandardError => e
      log_error("Token fetch failed: #{e.message}")
      nil
    end

    # Build API headers with authorization
    #
    # @param access_token [String] OAuth2 access token
    # @param vendor_id [String] Coupang vendor ID
    # @return [Hash] Headers hash
    def build_headers(access_token, vendor_id)
      {
        'Authorization' => "Bearer #{access_token}",
        'X-VENDOR-ID' => vendor_id,
        'Content-Type' => 'application/json'
      }
    end

    # Format product data for Coupang API
    #
    # @param listing [MarketplaceListing] The listing
    # @return [Hash] Coupang API product format
    def format_coupang_product(listing)
      catalog_product = listing.catalog_product
      base_data = format_product_data(listing)

      {
        sellerProductId: listing.marketplace_product_id || "CP-#{SecureRandom.hex(8)}",
        name: base_data[:title],
        detailContent: base_data[:description],
        salesType: 'SALE',
        saleStatus: 'ON_SALE',
        price: base_data[:price],
        discountedPrice: base_data[:price],
        discountRate: 0,
        brandName: listing.brand_name || catalog_product.brand,
        categoryId: listing.marketplace_category_id,
        images: base_data[:images].map { |url| { imageUrl: url } },
        items: format_items(base_data[:variants])
      }.compact
    end

    # Format items (variants) for Coupang API
    #
    # @param variants [Array<Hash>] Product variants
    # @return [Array<Hash>] Formatted items
    def format_items(variants)
      return [{ itemNo: '1', color: '기본', size: '기본', price: 0, salePrice: 0, stock: 10 }] if variants.empty?

      variants.map.with_index do |variant, index|
        {
          itemNo: (index + 1).to_s,
          color: variant[:name] || '기본',
          size: variant[:sku] || '기본',
          price: variant[:price],
          salePrice: variant[:price],
          stock: variant[:stock]
        }
      end
    end

    # Map Coupang order status to internal status
    #
    # @param status [String] Coupang order status
    # @return [String] Internal order status
    def map_order_status(status)
      case status
      when 'REQUESTED', 'PAID', 'READY'
        'pending'
      when 'DELIVERING'
        'processing'
      when 'DELIVERED'
        'delivered'
      when 'COMPLETED'
        'completed'
      when 'CANCEL_REQUESTED', 'CANCELLED'
        'cancelled'
      when 'RETURN_REQUESTED', 'RETURN_PROCESSING'
        'returning'
      when 'RETURNED'
        'returned'
      when 'EXCHANGE_REQUESTED', 'EXCHANGE_PROCESSING'
        'exchanging'
      when 'EXCHANGED'
        'exchanged'
      else
        'unknown'
      end
    end
  end
end
