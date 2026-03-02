# frozen_string_literal: true

# Naver Smart Store adapter for publishing listings
# Official API: https://developers.naver.com/doc/smartstore/
module Marketplace
  class SmartStoreAdapter < BaseAdapter
    # Naver Smart Store API endpoints
    BASE_URL = 'https://api.commerce.naver.com'
    OAUTH_URL = 'https://api.commerce.naver.com/external/v1/oauth2/token'

    # Publish a listing to Smart Store
    #
    # @param listing [MarketplaceListing] The listing to publish
    # @return [Hash] Result with marketplace_product_id and marketplace_url
    def publish(listing)
      credential = get_api_credential(listing.account, 'smart_store')
      return { success: false, error: 'Smart Store API 자격 증명이 필요합니다.' } unless credential

      begin
        # Get access token
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        # Format product data for Smart Store API
        product_data = format_smart_store_product(listing)

        # Make API request to register product
        response = execute_with_retry do
          HTTPX.post(
            "#{BASE_URL}/channel/v1/channels/#{credential.access_key}/products",
            headers: build_headers(access_token),
            json: product_data,
            timeout: DEFAULT_TIMEOUT
          )
        end

        result = handle_response(response, listing, { action: 'publish' })

        if result[:success]
          product_id = result.dig(:data, 'channelProductNo')
          create_audit_log(listing, 'publish', {
            marketplace_product_id: product_id,
            status: 'published'
          })
          {
            success: true,
            marketplace_product_id: product_id,
            marketplace_url: "https://smartstore.naver.com/products/#{product_id}"
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
      credential = get_api_credential(listing.account, 'smart_store')
      return { success: false, error: 'Smart Store API 자격 증명이 필요합니다.' } unless credential

      return { success: false, error: '마켓플레이스 제품 ID가 필요합니다.' } unless listing.marketplace_product_id

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        product_data = format_smart_store_product(listing)

        response = execute_with_retry do
          HTTPX.put(
            "#{BASE_URL}/channel/v1/channels/#{credential.access_key}/products/#{listing.marketplace_product_id}",
            headers: build_headers(access_token),
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
      credential = get_api_credential(listing.account, 'smart_store')
      return { success: false, error: 'Smart Store API 자격 증명이 필요합니다.' } unless credential

      return { success: false, error: '마켓플레이스 제품 ID가 필요합니다.' } unless listing.marketplace_product_id

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        response = execute_with_retry do
          HTTPX.put(
            "#{BASE_URL}/channel/v1/channels/#{credential.access_key}/products/#{listing.marketplace_product_id}/status",
            headers: build_headers(access_token),
            json: { sellStatus: 'STOP_SELL' }, # STOP_SELL = 판매 중지
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

      # Basic validation
      catalog_product = listing.catalog_product

      errors << '제목이 필요합니다.' if catalog_product.translated_title.blank?
      errors << '가격이 필요합니다.' if listing.listing_price_krw.zero?
      errors << '카테고리가 필요합니다.' if listing.marketplace_category_id.blank?
      errors << '상품 이미지가 필요합니다.' if catalog_product.processed_images.empty?

      # Smart Store specific validation
      if catalog_product.translated_title && catalog_product.translated_title.length > 100
        warnings << '제목이 너무 길 수 있습니다 (권장 100자 이내).'
      end

      if catalog_product.translated_description && catalog_product.translated_description.length > 5000
        errors << '상세 설명이 너무 깁니다 (최대 5000자).'
      end

      # Validate required fields for Smart Store
      unless listing.brand_name.present?
        warnings << '브랜드명이 설정되지 않았습니다.'
      end

      unless listing.origin_country.present?
        errors << '원산지 정보가 필요합니다.'
      end

      {
        valid: errors.empty?,
        errors:,
        warnings:
      }
    end

    # Sync order status from Smart Store
    #
    # @param order [Order] The order to sync
    # @return [Hash] Updated order data
    def sync_order(order)
      credential = get_api_credential(order.account, 'smart_store')
      return { success: false, error: 'Smart Store API 자격 증명이 필요합니다.' } unless credential

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        response = execute_with_retry do
          HTTPX.get(
            "#{BASE_URL}/channel/v1/channels/#{credential.access_key}/orders/#{order.marketplace_order_id}",
            headers: build_headers(access_token),
            timeout: DEFAULT_TIMEOUT
          )
        end

        result = handle_response(response, nil, { action: 'sync_order', order_id: order.id })

        if result[:success]
          order_data = result[:data]
          {
            success: true,
            status: map_order_status(order_data.dig('orderStatus')),
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
          client_secret: credential.secret_key,
          type: 'SELF'
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
    # @return [Hash] Headers hash
    def build_headers(access_token)
      {
        'Authorization' => "Bearer #{access_token}",
        'Content-Type' => 'application/json'
      }
    end

    # Format product data for Smart Store API
    #
    # @param listing [MarketplaceListing] The listing
    # @return [Hash] Smart Store API product format
    def format_smart_store_product(listing)
      catalog_product = listing.catalog_product
      base_data = format_product_data(listing)

      {
        channelProductNo: listing.marketplace_product_id,
        name: base_data[:title],
        detail: base_data[:description],
        mobileDetail: base_data[:description], # Mobile-friendly description
        saleType: 'SALE', # SALE = 판매 중
        sellStatus: 'SELLING', # SELLING = 판매중
        displayStatus: 'DISPLAY', # DISPLAY = 진열중
        supplyPrice: base_data[:price], # 공급가
        consumerPrice: (base_data[:price] * 1.1).to_i, # 소비자가 (10% 마진 포함)
        discountRate: 0,
        discountPrice: base_data[:price],
        brandName: listing.brand_name || catalog_product.brand,
        originCountryCode: listing.origin_country || 'KR', # 원산지 (KR=한국, CN=중국)
        manufacturerName: listing.manufacturer_name || '',
        manufacturerCountryCode: listing.manufacturer_country || 'KR',
        categoryCode: listing.marketplace_category_id,
        images: format_images(base_data[:images]),
        options: format_options(base_data[:variants]),
        adultProductYn: 'N', # 성인상품 여부
        afterServiceServiceCenterName: listing.cs_center_name || '',
        afterServicePhoneNumber: listing.cs_phone_number || '',
        afterServiceGuideUrl: listing.cs_guide_url || ''
      }.compact
    end

    # Format product images for Smart Store API
    #
    # @param images [Array<String>] Image URLs
    # @return [Array<Hash>] Formatted images
    def format_images(images)
      images.map.with_index do |url, index|
        {
          imageUrl: url,
          representativeImageYn: index.zero? ? 'Y' : 'N', # 첫 번째 이미지는 대표이미지
          altText: ''
        }
      end
    end

    # Format product options for Smart Store API
    #
    # @param variants [Array<Hash>] Product variants
    # @return [Array<Hash>] Formatted options
    def format_options(variants)
      return [{ optionName: '기본', optionValues: [{ optionValue: '기본', useYn: 'Y', stockQuantity: 10, price: 0 }] }] if variants.empty?

      variants.map do |variant|
        {
          optionName: variant[:name],
          optionValues: [
            {
              optionValue: variant[:sku],
              useYn: 'Y',
              stockQuantity: variant[:stock],
              price: variant[:price]
            }
          ]
        }
      end
    end

    # Map Smart Store order status to internal status
    #
    # @param status [String] Smart Store order status
    # @return [String] Internal order status
    def map_order_status(status)
      case status
      when 'ORDER_REQUESTED', 'PAYED', 'APPROVED'
        'pending'
      when 'PRODUCT_PREPARING', 'IN_DELIVERY'
        'processing'
      when 'DELIVERED'
        'delivered'
      when 'PURCHASE_CONFIRMED'
        'completed'
      when 'CANCEL_REQUESTED', 'CANCEL_DONE'
        'cancelled'
      when 'EXCHANGE_REQUESTED', 'EXCHANGE_IN_PROGRESS', 'EXCHANGE_DELIVERING', 'EXCHANGE_DONE'
        'exchanged'
      when 'RETURN_REQUESTED', 'RETURN_IN_PROGRESS', 'RETURN_DONE'
        'returned'
      else
        'unknown'
      end
    end
  end
end
