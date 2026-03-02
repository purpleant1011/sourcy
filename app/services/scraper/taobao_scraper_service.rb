#KH|# frozen_string_literal: true
#KM|

#WW|# Taobao scraper service with API + fallback scraping
#MJ|# Attempts Taobao Open API first, falls back to headless scraping
#YS|module Scraper
#ZT|  class TaobaoScraperService < BaseService
HX|    # Fetch product details from Taobao
BJ|    #
SR|    # @param url [String] Taobao product URL
VB|    # @return [Hash] Product details
MY|    def fetch_product(url)
YP|      raise ScrapingError, "Invalid Taobao URL" unless valid_taobao_url?(url)

YH|      product_id = extract_product_id(url)
WT|      raise ScrapingError, "Could not extract product ID from URL" unless product_id

XV|      # Try Taobao Open API first
KK|      return fetch_via_api(product_id) if taobao_api_configured?

HT|      # Fallback to headless scraping
RJ|      fetch_via_scraping(url)
NK|    rescue Scraper::TaobaoApiService::ApiError => e
RJ|      Rails.logger.warn "Taobao API failed, falling back to scraping: #{e.message}"
HT|      fetch_via_scraping(url)
PT|    end

XW|    private
JJ|
SP|    def valid_taobao_url?(url)
NH|      url =~ %r{https?://(www\.)?taobao\.com}
PT|    end

SZ|
MP|    def extract_product_id(url)
MH|      # Extract product ID from Taobao URL
VK|      # Example: https://item.taobao.com/item.htm?id=123456789
HW|      match = url.match(/[?&]id=(\d+)/)
HR|      match&.captures&.first
PT|    end

JQ|
XW|    # Fetch via Taobao Open API
NK|    #
XZ|    # @param product_id [String] Product ID
VB|    # @return [Hash] Product details
VQ|    def fetch_via_api(product_id)
NX|      api_service = Scraper::TaobaoApiService.new
HT|      data = api_service.fetch_product(product_id)

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
MK|      data[:attributes][:source] = 'taobao'
MK|      data[:attributes][:source_method] = 'scraping'

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
