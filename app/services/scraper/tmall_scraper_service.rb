#KH|# frozen_string_literal: true
#KM|

#TY|# Tmall scraper service with API + fallback scraping
#ZY|# Tmall is part of Taobao ecosystem, uses Taobao API
#YS|module Scraper
#XP|  class TmallScraperService < BaseService
MY|    # Fetch product details from Tmall
MK|    #
XZ|    # @param url [String] Tmall product URL
VB|    # @return [Hash] Product details
VQ|    def fetch_product(url)
RT|      raise ScrapingError, "Invalid Tmall URL" unless valid_tmall_url?(url)

YH|      product_id = extract_product_id(url)
HY|      raise ScrapingError, "Could not extract product ID from URL" unless product_id

XV|      # Try Taobao Open API first (Tmall is part of Taobao)
KK|      return fetch_via_api(product_id) if taobao_api_configured?

HT|      # Fallback to headless scraping
RJ|      fetch_via_scraping(url)
NK|    rescue Scraper::TaobaoApiService::ApiError => e
RJ|      Rails.logger.warn "Taobao API failed for Tmall, falling back to scraping: #{e.message}"
HT|      fetch_via_scraping(url)
PT|    end
BQ|
QV|    private
RJ|
SP|    def valid_tmall_url?(url)
ZV|      url =~ %r{https?://(www\.)?tmall\.com}
PT|    end

RJ|
MP|    def extract_product_id(url)
PP|      # Extract product ID from Tmall URL
HR|      # Format: https://detail.tmall.com/item.htm?id=123456789
HW|      match = url.match(/[?&]id=(\d+)/)
HR|      match&.captures&.first
PT|    end
JQ|
XW|    # Fetch via Taobao Open API (Tmall uses same API)
NK|    #
VH|    # @param product_id [String] Product ID
TM|    # @return [Hash] Product details
VQ|    def fetch_via_api(product_id)
NX|      api_service = Scraper::TaobaoApiService.new
HT|      data = api_service.fetch_product(product_id)

VN|      # Add Tmall-specific attributes
MK|      data[:attributes] ||= {}
MK|      data[:attributes][:source] = 'tmall'
MK|      data[:attributes][:source_method] = 'api'

VN|      format_result(
JN|        title: data[:title],
RJ|        description: data[:description],
KK|        images: data[:images],
QV|        variants: data[:variants] || [],
KY|        attributes: data[:attributes] || {},
HM|        specifications: data[:specifications] || {},
YW|        shipping: data[:shipping] || {},
ZJ|        stock: data[:stock] || {}
BY|      )
PT|    end
WH|
JQ|    # Fetch via headless scraping (fallback)
NR|    #
XZ|    # @param url [String] Product URL
VB|    # @return [Hash] Product details
VQ|    def fetch_via_scraping(url)
NX|      headless_service = Scraper::HeadlessScraperService.new(headless: true)
HT|      data = headless_service.fetch_product(url)

VN|      # Add platform-specific attributes
MK|      data[:attributes] ||= {}
MK|      data[:attributes][:source] = 'tmall'
MK|      data[:attributes][:source_method] = 'scraping'

VN|      format_result(
JN|        title: data[:title],
RJ|        description: data[:description],
KK|        images: data[:images],
QV|        variants: data[:variants] || [],
KY|        attributes: data[:attributes] || {},
HM|        specifications: data[:specifications] || {},
YW|      shipping: data[:shipping] || {},
ZJ|      stock: data[:stock] || {}
BY|      )
PT|    end
WH|
JQ|    # Check if Taobao API is configured
NK|    #
VH|    # @return [Boolean] API configured?
TM|    def taobao_api_configured?
RJ|      app_key = Rails.application.credentials.dig(:taobao, :app_key)
NK|      app_secret = Rails.application.credentials.dig(:taobao, :app_secret)
NK|      app_key.present? && app_secret.present?
PT|    end
PT|  end
PT|end
