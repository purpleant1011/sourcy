# frozen_string_literal: true

# Taobao Open API service for official API access
# Requires Taobao Open API credentials (app_key, app_secret)
# API Docs: https://open.taobao.com/doc.htm?spm=a219a.7629140.0.0.6e76667aUoRgM0&source=search&docType=1
module Scraper
  class TaobaoApiService
    class ApiError < StandardError; end

    API_BASE_URL = 'https://eco.taobao.com/router/rest'
    API_VERSION = '2.0'

    attr_reader :app_key, :app_secret

    def initialize(app_key: nil, app_secret: nil)
      @app_key = app_key || Rails.application.credentials.dig(:taobao, :app_key)
      @app_secret = app_secret || Rails.application.credentials.dig(:taobao, :app_secret)

      raise ApiError, 'Taobao API credentials not configured' unless @app_key && @app_secret
    end

    # Fetch product details using Taobao Open API
    #
    # @param product_id [String, Integer] Taobao product ID
    # @return [Hash] Product details in standard format
    def fetch_product(product_id)
      raise ApiError, 'Product ID is required' unless product_id

      params = build_api_params('taobao.item.get', num_iid: product_id, fields: product_fields)

      response = make_api_request(params)
      parse_product_response(response)
    end

    # Search products by keyword
    #
    # @param keyword [String] Search keyword
    # @param page [Integer] Page number (default: 1)
    # @param page_size [Integer] Items per page (default: 20, max: 100)
    # @return [Hash] Search results
    def search_products(keyword, page: 1, page_size: 20)
      raise ApiError, 'Keyword is required' unless keyword

      params = build_api_params(
        'taobao.items.search',
        q: keyword,
        page_no: page,
        page_size: [page_size, 100].min,
        fields: search_fields
      )

      response = make_api_request(params)
      parse_search_response(response)
    end

    # Get shop information
    #
    # @param seller_id [String, Integer] Seller/Shop ID
    # @return [Hash] Shop details
    def fetch_shop(seller_id)
      raise ApiError, 'Seller ID is required' unless seller_id

      params = build_api_params(
        'taobao.shop.get',
        nick: seller_id,
        fields: 'sid,cid,title,desc,bulletin,pic_path,created,modified'
      )

      response = make_api_request(params)
      parse_shop_response(response)
    end

    private

    # Build API parameters with signature
    #
    # @param method [String] API method name
    # @param params [Hash] API-specific parameters
    # @return [Hash] Complete API parameters
    def build_api_params(method, params = {})
      timestamp = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

      base_params = {
        method: method,
        app_key: app_key,
        timestamp: timestamp,
        format: 'json',
        v: API_VERSION,
        sign_method: 'md5'
      }.merge(params)

      base_params[:sign] = generate_signature(base_params)
      base_params
    end

    # Generate MD5 signature for API request
    #
    # @param params [Hash] API parameters
    # @return [String] MD5 signature (uppercase)
    def generate_signature(params)
      sorted_params = params.sort_by { |k, _| k.to_s }.map { |k, v| "#{k}#{v}" }.join
      sign_string = app_secret + sorted_params + app_secret

      Digest::MD5.hexdigest(sign_string).upcase
    end

    # Make API request using httpx
    #
    # @param params [Hash] API parameters
    # @return [Hash] Parsed JSON response
    def make_api_request(params)
      response = HTTPX.timeout(30)
                       .post(API_BASE_URL, form: params)

      unless response.status == 200
        raise ApiError, "HTTP #{response.status}: #{response.body.to_s[0..200]}"
      end

      data = JSON.parse(response.body.to_s)

      # Check for API error responses
      if data['error_response']
        error_msg = data['error_response']['msg'] || 'Unknown API error'
        error_code = data['error_response']['code'] || 'unknown'
        raise ApiError, "API Error (#{error_code}): #{error_msg}"
      end

      data
    end

    # Parse Taobao item API response
    #
    # @param response [Hash] API response
    # @return [Hash] Formatted product details
    def parse_product_response(response)
      item = response.dig('taobao_item_get_response', 'item')

      return {} unless item

      {
        id: item['num_iid'],
        title: item['title'],
        description: item['desc'],
        price_cents: parse_price(item['price']),
        original_price_cents: parse_price(item['reserve_price']),
        images: parse_images(item),
        variants: parse_variants(item),
        attributes: {
          brand: item['property_alias'] || 'Unknown',
          origin: 'China',
          category: item['cid'],
          seller_id: item['nick'],
          shop_title: item['shop_title']
        },
        specifications: parse_specifications(item),
        shipping: {
          domestic: item['delivery_fee'] == '0.00',
          free_shipping: item['delivery_fee'] == '0.00',
          shipping_days: item['express_fee'] ? 3 : nil
        },
        stock: {
          available: item['num'].to_i,
          status: item['num'].to_i > 0 ? 'in_stock' : 'out_of_stock'
        },
        raw_api_data: item
      }
    end

    # Parse search API response
    #
    # @param response [Hash] API response
    # @return [Hash] Search results
    def parse_search_response(response)
      result = response.dig('taobao_items_search_response', 'items', 'item_list')

      {
        total_count: response.dig('taobao_items_search_response', 'total_results')&.to_i || 0,
        items: Array(result).map { |item| parse_search_item(item) }
      }
    end

    # Parse single search result item
    #
    # @param item [Hash] Item data
    # @return [Hash] Parsed item
    def parse_search_item(item)
      {
        id: item['num_iid'],
        title: item['title'],
        price_cents: parse_price(item['price']),
        image_url: item['pic_url'],
        shop_title: item['nick'],
        sales_count: item['volume'].to_i
      }
    end

    # Parse shop API response
    #
    # @param response [Hash] API response
    # @return [Hash] Shop details
    def parse_shop_response(response)
      shop = response.dig('taobao_shop_get_response', 'shop')

      return {} unless shop

      {
        id: shop['sid'],
        nick: shop['nick'],
        title: shop['title'],
        description: shop['desc'],
        bulletin: shop['bulletin'],
        logo_url: shop['pic_url'],
        created_at: shop['created'],
        modified_at: shop['modified']
      }
    end

    # Parse price string to cents
    #
    # @param price [String] Price string (e.g., "100.50")
    # @return [Integer] Price in cents
    def parse_price(price)
      return 0 unless price

      (price.to_f * 100).to_i
    end

    # Parse images from item data
    #
    # @param item [Hash] Item data
    # @return [Array<String>] Image URLs
    def parse_images(item)
      images = []

      # Main image
      images << item['pic_url'] if item['pic_url']

      # Additional images
      if item['item_imgs'] && item['item_imgs']['item_img']
        images.concat(Array(item['item_imgs']['item_img']).map { |img| img['url'] })
      end

      images.uniq.compact
    end

    # Parse product variants (SKUs)
    #
    # @param item [Hash] Item data
    # @return [Array<Hash>] Product variants
    def parse_variants(item)
      return [] unless item['skus'] && item['skus']['sku']

      Array(item['skus']['sku']).map do |sku|
        {
          id: sku['sku_id'],
          name: sku['properties_name'] || 'Variant',
          price_cents: parse_price(sku['price']),
          available: sku['quantity'].to_i > 0,
          stock_quantity: sku['quantity'].to_i
        }
      end
    end

    # Parse product specifications
    #
    # @param item [Hash] Item data
    # @return [Hash] Specifications
    def parse_specifications(item)
      specs = {}

      if item['props'] && item['props']['prop']
        Array(item['props']['prop']).each do |prop|
          key = prop['vid'] || prop['pid']
          value = prop['name'] || prop['value']
          specs[key] = value
        end
      end

      # Additional specs from props_name
      if item['props_name']
        item['props_name'].split(';').each do |prop_str|
          parts = prop_str.split(':')
          if parts.length >= 2
            key = parts[1]
            value = parts[2]
            specs[key] = value
          end
        end
      end

      specs
    end

    # Fields to request for product details
    #
    # @return [String] Comma-separated field names
    def product_fields
      [
        'num_iid', 'title', 'desc', 'price', 'reserve_price', 'num', 'detail_url',
        'pic_url', 'item_imgs', 'props', 'props_name', 'skus', 'seller_id',
        'shop_title', 'property_alias', 'delivery_fee', 'express_fee', 'created'
      ].join(',')
    end

    # Fields to request for search results
    #
    # @return [String] Comma-separated field names
    def search_fields
      [
        'num_iid', 'title', 'price', 'pic_url', 'nick', 'volume'
      ].join(',')
    end
  end
end
