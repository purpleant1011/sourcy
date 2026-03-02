# frozen_string_literal: true

# 11st (11번가) adapter for publishing listings
# Official API: https://developer.11st.co.kr/
module Marketplace
  class ElevenstAdapter < BaseAdapter
    # 11st API endpoints
    BASE_URL = 'https://api.11st.co.kr'
    OAUTH_URL = 'https://api.11st.co.kr/oauth/token'

    # Publish a listing to 11st
    #
    # @param listing [MarketplaceListing] The listing to publish
    # @return [Hash] Result with marketplace_product_id and marketplace_url
    def publish(listing)
      credential = get_api_credential(listing.account, 'elevenst')
      return { success: false, error: '11st API 자격 증명이 필요합니다.' } unless credential

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        product_data = format_elevenst_product(listing)

        response = execute_with_retry do
          HTTPX.post(
            "#{BASE_URL}/products",
            headers: build_headers(access_token, credential.access_key),
            json: product_data,
            timeout: DEFAULT_TIMEOUT
          )
        end

        result = handle_response(response, listing, { action: 'publish' })

        if result[:success]
          product_id = result.dig(:data, 'productNo')
          create_audit_log(listing, 'publish', {
            marketplace_product_id: product_id,
            status: 'published'
          })
          {
            success: true,
            marketplace_product_id: product_id,
            marketplace_url: "https://www.11st.co.kr/products/#{product_id}"
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
      credential = get_api_credential(listing.account, 'elevenst')
      return { success: false, error: '11st API 자격 증명이 필요합니다.' } unless credential

      return { success: false, error: '마켓플레이스 제품 ID가 필요합니다.' } unless listing.marketplace_product_id

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        product_data = format_elevenst_product(listing)

        response = execute_with_retry do
          HTTPX.put(
            "#{BASE_URL}/products/#{listing.marketplace_product_id}",
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
      credential = get_api_credential(listing.account, 'elevenst')
      return { success: false, error: '11st API 자격 증명이 필요합니다.' } unless credential

      return { success: false, error: '마켓플레이스 제품 ID가 필요합니다.' } unless listing.marketplace_product_id

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        response = execute_with_retry do
          HTTPX.put(
            "#{BASE_URL}/products/#{listing.marketplace_product_id}/status",
            headers: build_headers(access_token, credential.access_key),
            json: { displayYn: 'N' },
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

      # 11st specific validation
      if catalog_product.translated_title && catalog_product.translated_title.length > 100
        warnings << '제목이 너무 길 수 있습니다 (권장 100자 이내).'
      end

      if catalog_product.translated_description && catalog_product.translated_description.length > 5000
        errors << '상세 설명이 너무 깁니다 (최대 5000자).'
      end

      {
        valid: errors.empty?,
        errors:,
        warnings:
      }
    end

    # Sync order status from 11st
    #
    # @param order [Order] The order to sync
    # @return [Hash] Updated order data
    def sync_order(order)
      credential = get_api_credential(order.account, 'elevenst')
      return { success: false, error: '11st API 자격 증명이 필요합니다.' } unless credential

      begin
        access_token = get_access_token(credential)
        return { success: false, error: '토큰 발급에 실패했습니다.' } unless access_token

        response = execute_with_retry do
          HTTPX.get(
            "#{BASE_URL}/orders/#{order.marketplace_order_id}",
            headers: build_headers(access_token, credential.access_key),
            timeout: DEFAULT_TIMEOUT
          )
        end

        result = handle_response(response, nil, { action: 'sync_order', order_id: order.id })

        if result[:success]
          order_data = result[:data]
          {
            success: true,
            status: map_order_status(order_data.dig('orderStatus')),
            updated_at: order_data.dig('updateDate')
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
    # @param api_key [String] 11st API key
    # @return [Hash] Headers hash
    def build_headers(access_token, api_key)
      {
        'Authorization' => "Bearer #{access_token}",
        'openapi': api_key,
        'Content-Type' => 'application/json'
      }
    end

    # Format product data for 11st API
    #
    # @param listing [MarketplaceListing] The listing
    # @return [Hash] 11st API product format
    def format_elevenst_product(listing)
      catalog_product = listing.catalog_product
      base_data = format_product_data(listing)

      {
        prdNo: listing.marketplace_product_id || "11ST-#{SecureRandom.hex(8)}",
        prdNm: base_data[:title],
        prdDetail: base_data[:description],
        sellPr: base_data[:price],
        dispPr: base_data[:price],
        dispYn: 'Y',
        cateCd: listing.marketplace_category_id,
        images: base_data[:images].map { |url| { imgUrl: url } },
        options: format_elevenst_options(base_data[:variants])
      }.compact
    end

    # Format options for 11st API
    #
    # @param variants [Array<Hash>] Product variants
    # @return [Array<Hash>] Formatted options
    def format_elevenst_options(variants)
      return [{ optCd: '01', optNm: '기본', addPr: 0, selPrc: 10 }] if variants.empty?

      variants.map.with_index do |variant, index|
        {
          optCd: format('%02d', index + 1),
          optNm: variant[:name] || '기본',
          addPr: variant[:price],
          selPrc: variant[:stock]
        }
      end
    end

    # Map 11st order status to internal status
    #
    # @param status [String] 11st order status
    # @return [String] Internal order status
    def map_order_status(status)
      case status
      when 'PAID', 'APPROVED'
        'pending'
      when 'PREPARING', 'SHIPPING'
        'processing'
      when 'DELIVERED'
        'delivered'
      when 'COMPLETED'
        'completed'
      when 'CANCELLING', 'CANCELLED'
        'cancelled'
      when 'RETURN_REQUESTED', 'RETURNING'
        'returning'
      when 'RETURNED'
        'returned'
      when 'EXCHANGING'
        'exchanging'
      when 'EXCHANGED'
        'exchanged'
      else
        'unknown'
      end
    end
  end
end
