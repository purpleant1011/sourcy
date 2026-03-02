# frozen_string_literal: true

# Base scraper service for extracting product data from e-commerce platforms
module Scraper
  class BaseService
    class ScrapingError < StandardError; end

    attr_reader :options

    # Initialize scraper service
    #
    # @param options [Hash] Additional options for scraping
    def initialize(options: {})
      @options = options
    end

    # Fetch product details from a URL
    #
    # @abstract
    # @param url [String] Product URL
    # @return [Hash] Product details
    # @raise [NotImplementedError] if subclass doesn't implement
    def fetch_product(url)
      raise NotImplementedError, "Subclasses must implement #fetch_product"
    end

    protected

    # Make HTTP request with retry logic using Rails 8 httpx
    #
    # @param url [String] URL to request
    # @param headers [Hash] Request headers
    # @param method [Symbol] HTTP method (:get, :post, etc.)
    # @param body [Hash, nil] Request body for non-GET requests
    # @return [HTTPX::Response]
    def make_request(url, headers: {}, method: :get, body: nil)
      response = HTTPX.timeout(30)
                     .follow(max_hops: 5)
                     .with_headers(default_headers.merge(headers))
                     .with(user_agent: random_user_agent)
                     .public_send(method, url, json: body)

      unless response.status < 400
        raise ScrapingError, "HTTP #{response.status}: #{response.body.to_s[0..200]}"
      end

      response
    end

    # Default request headers
    #
    # @return [Hash]
    def default_headers
      {
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language' => 'ko-KR,ko;q=0.9,en;q=0.8',
        'Accept-Encoding' => 'gzip, deflate, br',
        'Connection' => 'keep-alive',
        'Upgrade-Insecure-Requests' => '1'
      }
    end

    # Get random user agent to avoid blocking
    #
    # @return [String] User agent string
    def random_user_agent
      user_agents = [
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15'
      ]

      user_agents.sample
    end

    # Parse HTML from response
    #
    # @param response [HTTPX::Response] HTTP response
    # @return [Nokogiri::HTML::Document]
    def parse_html(response)
      Nokogiri::HTML(response.body.to_s)
    end

    # Extract product ID from URL
    #
    # @param url [String] Product URL
    # @return [String, nil] Product ID
    def extract_product_id(url)
      nil # Subclasses should implement
    end

    # Format product details to standard structure
    #
    # @param title [String] Product title
    # @param description [String] Product description
    # @param images [Array<String>] Image URLs
    # @param variants [Array<Hash>] Product variants
    # @param attributes [Hash] Product attributes
    # @return [Hash] Formatted product details
    def format_result(title:, description: "", images: [], variants: [], attributes: {})
      {
        title: title,
        description: description,
        images: images,
        variants: variants,
        attributes: attributes,
        specifications: {},
        shipping: {},
        stock: {}
      }
    end
  end
end
