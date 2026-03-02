# frozen_string_literal: true

# Amazon Product Advertising API v5 service
# Requires AWS credentials and Partner Tag (Tracking ID)
# API Docs: https://webservices.amazon.com/paapi5/documentation/
module Scraper
  class AmazonPaapiService
    class ApiError < StandardError; end

    API_BASE_URLS = {
      'us-east-1' => 'https://webservices.amazon.com',
      'eu-west-1' => 'https://webservices.amazon.co.uk',
      'ap-northeast-1' => 'https://webservices.amazon.co.jp'
    }.freeze

    attr_reader :access_key, :secret_key, :partner_tag, :region

    def initialize(
      access_key: nil,
      secret_key: nil,
      partner_tag: nil,
      region: 'us-east-1'
    )
      @access_key = access_key || Rails.application.credentials.dig(:amazon, :access_key)
      @secret_key = secret_key || Rails.application.credentials.dig(:amazon, :secret_key)
      @partner_tag = partner_tag || Rails.application.credentials.dig(:amazon, :partner_tag)
      @region = region

      raise ApiError, 'Amazon PAAPI credentials not configured' unless @access_key && @secret_key && @partner_tag
    end

    # Fetch product details by ASIN
    #
    # @param asin [String] Amazon ASIN
    # @param resources [Array<String>] Additional resources to fetch
    # @return [Hash] Product details
    def fetch_product(asin, resources: default_product_resources)
      raise ApiError, 'ASIN is required' unless asin

      params = {
        'ItemIds' => [asin],
        'Resources' => resources,
        'Condition' => 'New'
      }

      response = make_api_request('GetItems', params)
      parse_product_response(response, asin)
    end

    # Search products by keyword
    #
    # @param keyword [String] Search keyword
    # @param search_index [String] Category (e.g., 'All', 'Books', 'Electronics')
    # @param page [Integer] Page number (1-10)
    # @param page_size [Integer] Items per page (1-100)
    # @return [Hash] Search results
    def search_products(keyword, search_index: 'All', page: 1, page_size: 10)
      raise ApiError, 'Keyword is required' unless keyword

      params = {
        'Keywords' => keyword,
        'SearchIndex' => search_index,
        'ItemPage' => page,
        'Resources' => search_resources,
        'ItemCount' => page_size
      }

      response = make_api_request('SearchItems', params)
      parse_search_response(response)
    end

    # Get product variations
    #
    # @param asin [String] Parent ASIN
    # @return [Hash] Product variations
    def get_variations(asin)
      raise ApiError, 'ASIN is required' unless asin

      params = {
        'ASIN' => asin,
        'VariationPage' => 1,
        'Resources' => variation_resources
      }

      response = make_api_request('GetVariations', params)
      parse_variations_response(response)
    end

    private

    # Default resources for product details
    #
    # @return [Array<String>] Resource names
    def default_product_resources
      [
        'Images.Primary.Medium',
        'Images.Primary.Large',
        'Images.Variants.Medium',
        'ItemInfo.Title',
        'ItemInfo.Features',
        'ItemInfo.ProductInfo',
        'ItemInfo.TechnicalInfo',
        'ItemInfo.TradeInInfo',
        'Offers.Listings.Price',
        'Offers.Listings.MerchantInfo',
        'Offers.Listings.Condition',
        'Offers.Listings.DeliveryInfo',
        'Offers.Summaries.LowestPrice',
        'Offers.Summaries.HighestPrice',
        'Offers.Summaries.OfferCount',
        'BrowseNodeInfo.BrowseNodes',
        'BrowseNodeInfo.BrowseNodes.Ancestor',
        'BrowseNodeInfo.BrowseNodes.SalesRank',
        'BrowseNodeInfo.WebsiteSalesRank',
        'ParentASIN'
      ]
    end

    # Resources for search results
    #
    # @return [Array<String>] Resource names
    def search_resources
      [
        'Images.Primary.Medium',
        'ItemInfo.Title',
        'ItemInfo.Features',
        'Offers.Listings.Price',
        'BrowseNodeInfo.BrowseNodes'
      ]
    end

    # Resources for product variations
    #
    # @return [Array<String>] Resource names
    def variation_resources
      [
        'Images.Primary.Medium',
        'ItemInfo.Title',
        'ItemInfo.Features',
        'Offers.Listings.Price',
        'VariationSummary.Price.HighestPrice',
        'VariationSummary.Price.LowestPrice',
        'VariationSummary.VariationCount'
      ]
    end

    # Make authenticated API request
    #
    # @param operation [String] PAAPI operation (e.g., 'GetItems', 'SearchItems')
    # @param params [Hash] Operation parameters
    # @return [Hash] API response
    def make_api_request(operation, params)
      host = API_BASE_URLS[region] || API_BASE_URLS['us-east-1']
      path = '/paapi5/searchitems' if operation == 'SearchItems'
      path = "/paapi5/#{operation.downcase}"

      # Build target
      target = "com.amazon.paapi5.#{operation}"

      # Prepare request
      timestamp = Time.now.utc
      amz_date = timestamp.strftime('%Y%m%dT%H%M%SZ')
      date_stamp = timestamp.strftime('%Y%m%d')

      # Build canonical request
      payload = JSON.generate(params)
      canonical_headers = build_canonical_headers(host, amz_date)
      signed_headers = build_signed_headers
      canonical_request = [
        'POST',
        path,
        '',
        canonical_headers,
        signed_headers,
        Digest::SHA256.hexdigest(payload)
      ].join("\n")

      # Build string to sign
      credential_scope = "#{date_stamp}/#{region}/paapi5/aws4_request"
      string_to_sign = [
        'AWS4-HMAC-SHA256',
        amz_date,
        credential_scope,
        Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")

      # Calculate signature
      signature = calculate_signature(date_stamp, region, string_to_sign)

      # Build authorization header
      authorization_header = [
        "AWS4-HMAC-SHA256 Credential=#{access_key}/#{credential_scope}",
        "SignedHeaders=#{signed_headers}",
        "Signature=#{signature}"
      ].join(',')

      # Make HTTP request
      headers = {
        'host' => host,
        'x-amz-date' => amz_date,
        'x-amz-target' => target,
        'content-type' => 'application/json; charset=utf-8',
        'authorization' => authorization_header
      }

      response = HTTPX.timeout(30)
                       .post("#{host}#{path}", headers: headers, body: payload)

      unless response.status == 200
        raise ApiError, "HTTP #{response.status}: #{response.body.to_s[0..200]}"
      end

      data = JSON.parse(response.body.to_s)

      # Check for PAAPI error responses
      if data['Errors']
        error_msg = data['Errors'].first['Message'] || 'Unknown PAAPI error'
        error_code = data['Errors'].first['Code'] || 'unknown'
        raise ApiError, "PAAPI Error (#{error_code}): #{error_msg}"
      end

      data
    end

    # Build canonical headers for AWS Signature V4
    #
    # @param host [String] API host
    # @param amz_date [String] AMZ date string
    # @return [String] Canonical headers
    def build_canonical_headers(host, amz_date)
      [
        "host:#{host}\n",
        "x-amz-date:#{amz_date}\n"
      ].join
    end

    # Build signed headers string
    #
    # @return [String] Signed headers
    def build_signed_headers
      'host;x-amz-date'
    end

    # Calculate AWS Signature V4
    #
    # @param date_stamp [String] Date stamp (YYYYMMDD)
    # @param region [String] AWS region
    # @param string_to_sign [String] String to sign
    # @return [String] Calculated signature
    def calculate_signature(date_stamp, region, string_to_sign)
      k_date = hmac_sha256("AWS4#{secret_key}", date_stamp)
      k_region = hmac_sha256(k_date, region)
      k_service = hmac_sha256(k_region, 'paapi5')
      k_signing = hmac_sha256(k_service, 'aws4_request')

      hmac_sha256_hex(k_signing, string_to_sign)
    end

    # HMAC SHA256 helper
    #
    # @param key [String, OpenSSL::Digest] Key for HMAC
    # @param data [String] Data to sign
    # @return [OpenSSL::Digest] HMAC digest
    def hmac_sha256(key, data)
      OpenSSL::HMAC.digest('SHA256', key, data)
    end

    # HMAC SHA256 hex helper
    #
    # @param key [String, OpenSSL::Digest] Key for HMAC
    # @param data [String] Data to sign
    # @return [String] Hex encoded HMAC
    def hmac_sha256_hex(key, data)
      OpenSSL::HMAC.hexdigest('SHA256', key, data)
    end

    # Parse GetItems response
    #
    # @param response [Hash] API response
    # @param asin [String] Requested ASIN
    # @return [Hash] Parsed product details
    def parse_product_response(response, asin)
      items = response.dig('ItemsResult', 'Items')
      return {} if items.nil? || items.empty?

      item = items.find { |i| i['ASIN'] == asin }
      return {} unless item

      parse_item_data(item)
    end

    # Parse SearchItems response
    #
    # @param response [Hash] API response
    # @return [Hash] Search results
    def parse_search_response(response)
      items = response.dig('SearchResult', 'Items') || []

      {
        total_result_count: response['TotalResultCount'] || 0,
        total_pages: response['TotalPages'] || 0,
        items: items.map { |item| parse_item_data(item) }
      }
    end

    # Parse GetVariations response
    #
    # @param response [Hash] API response
    # @return [Hash] Variations data
    def parse_variations_response(response)
      items = response.dig('ItemsResult', 'Items') || []

      {
        variation_count: response['VariationCount'] || 0,
        variations: items.map { |item| parse_item_data(item) }
      }
    end

    # Parse item data from PAAPI response
    #
    # @param item [Hash] Item data
    # @return [Hash] Formatted item
    def parse_item_data(item)
      item_info = item['ItemInfo'] || {}
      offers = item['Offers'] || {}
      images = item['Images'] || {}
      browse_node_info = item['BrowseNodeInfo'] || {}

      title = item_info.dig('Title', 'DisplayValue') || 'No title'
      features = item_info.dig('Features', 'DisplayValues') || []

      # Parse offers
      listings = offers.dig('Listings') || []
      listing = listings.find { |l| l['Condition'] && l['Condition']['Value'] == 'New' } || listings.first
      price = parse_price(listing)

      # Parse images
      primary_image = images.dig('Primary', 'Large', 'URL') || images.dig('Primary', 'Medium', 'URL')
      variant_images = images.dig('Variants') || []

      {
        id: item['ASIN'],
        title: title,
        description: features.join("\n"),
        price_cents: price[:price_cents],
        list_price_cents: price[:list_price_cents],
        images: parse_images(primary_image, variant_images),
        attributes: {
          brand: item_info.dig('ByLineInfo', 'Brand', 'DisplayValue') || 'Unknown',
          origin: determine_origin(item),
          category: parse_category(browse_node_info),
          asin: item['ASIN'],
          parent_asin: item['ParentASIN']
        },
        specifications: parse_specifications(item_info),
        shipping: parse_shipping(listing),
        stock: parse_stock(listing),
        raw_api_data: item
      }
    end

    # Parse price from listing
    #
    # @param listing [Hash] Listing data
    # @return [Hash] Price info
    def parse_price(listing)
      return { price_cents: 0, list_price_cents: 0 } unless listing

      price_info = listing.dig('Price') || {}
      savings_info = listing.dig('Price', 'Savings') || {}

      price_cents = parse_amount(price_info['Amount'])
      list_price_cents = parse_amount(savings_info['Percentage']) ? price_cents : parse_amount(price_info['AmountBeforeTax'])

      {
        price_cents: price_cents,
        list_price_cents: list_price_cents,
        currency: price_info['Currency']
      }
    end

    # Parse amount with currency
    #
    # @param amount [Hash] Amount object
    # @return [Integer] Amount in cents
    def parse_amount(amount)
      return 0 unless amount

      value = amount['Amount'] || amount
      (value.to_f * 100).to_i
    end

    # Parse images
    #
    # @param primary_image [String] Primary image URL
    # @param variant_images [Array<Hash>] Variant images
    # @return [Array<String>] Image URLs
    def parse_images(primary_image, variant_images)
      images = []
      images << primary_image if primary_image

      if variant_images
        images.concat(variant_images.map { |v| v.dig('Large', 'URL') || v.dig('Medium', 'URL') })
      end

      images.compact.uniq
    end

    # Parse product specifications
    #
    # @param item_info [Hash] Item info
    # @return [Hash] Specifications
    def parse_specifications(item_info)
      specs = {}

      if item_info['TechnicalInfo']
        item_info['TechnicalInfo']['Features']&.each do |feature|
          key = feature['Name']
          value = feature['DisplayValue']
          specs[key] = value
        end
      end

      if item_info['ProductInfo']
        item_info['ProductInfo']['Features']&.each do |feature|
          key = feature['Name']
          value = feature['DisplayValue']
          specs[key] = value
        end
      end

      specs
    end

    # Parse shipping info
    #
    # @param listing [Hash] Listing data
    # @return [Hash] Shipping info
    def parse_shipping(listing)
      return {} unless listing

      delivery_info = listing.dig('DeliveryInfo') || {}
      is_prime = delivery_info['IsPrimeEligible'] || false

      {
        domestic: true,
        free_shipping: is_prime,
        shipping_days: parse_delivery_days(delivery_info['IsAmazonFulfilled'])
      }
    end

    # Parse delivery days estimate
    #
    # @param is_fulfilled [Boolean] Is Amazon fulfilled
    # @return [Integer, nil] Delivery days
    def parse_delivery_days(is_fulfilled)
      return 2 if is_fulfilled
      nil
    end

    # Parse stock info
    #
    # @param listing [Hash] Listing data
    # @return [Hash] Stock info
    def parse_stock(listing)
      return {} unless listing

      availability = listing.dig('Availability', 'Message') || ''
      available = availability.downcase.include?('available') || availability.downcase.include?('in stock')

      {
        available: available,
        status: available ? 'in_stock' : 'out_of_stock'
      }
    end

    # Parse product category
    #
    # @param browse_node_info [Hash] Browse node info
    # @return [String] Category name
    def parse_category(browse_node_info)
      return 'Unknown' unless browse_node_info && browse_node_info['BrowseNodes']

      # Find leaf node (no children)
      nodes = browse_node_info['BrowseNodes']
      leaf_node = nodes.find { |n| !n['Ancestor'] } || nodes.last

      leaf_node.dig('DisplayValue') || leaf_node.dig('ContextFreeName') || 'Unknown'
    end

    # Determine product origin based on listing info
    #
    # @param item [Hash] Item data
    # @return [String] Origin
    def determine_origin(item)
      # PAAPI v5 doesn't directly provide origin, make best effort
      # This could be improved by analyzing seller info or other signals
      'International'
    end
  end
end
