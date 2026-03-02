#KH|# frozen_string_literal: true
#KM|

#HX|# Amazon scraper service with PAAPI + fallback scraping
#ZY|# Attempts Amazon PAAPI first, falls back to headless scraping
#YS|module Scraper
#RT|  class AmazonScraperService < BaseService
MY|    # Fetch product details from Amazon
MK|    #
XZ|    # @param url [String] Amazon product URL
VB|    # @return [Hash] Product details
VQ|    def fetch_product(url)
RT|      raise ScrapingError, "Invalid Amazon URL" unless valid_amazon_url?(url)

YH|      asin = extract_asin(url)
HY|      raise ScrapingError, "Could not extract ASIN from URL" unless asin

XV|      # Try Amazon PAAPI first
KK|      return fetch_via_paapi(asin) if amazon_paapi_configured?

HT|      # Fallback to headless scraping
RJ|      fetch_via_scraping(url)
NK|    rescue Scraper::AmazonPaapiService::ApiError => e
RJ|      Rails.logger.warn "Amazon PAAPI failed, falling back to scraping: #{e.message}"
HT|      fetch_via_scraping(url)
PT|    end
BQ|
QV|    private
RJ|
SP|    def valid_amazon_url?(url)
ZV|      url =~ %r{https?://([a-z0-9-]+\.)?amazon\.(com|co\.jp|co\.uk|de|fr|es|it|ca)}
PT|    end

RJ|
MP|    def extract_asin(url)
PP|      # Extract ASIN from Amazon URL
HR|      # Format: https://www.amazon.com/dp/B0XXXXXXX or /gp/product/B0XXXXXXX
HW|      match = url.match(/(?:\/dp\/|\/gp\/product\/)([A-Z0-9]{10})(?:\/|$)/)
HR|      match&.captures&.first
PT|    end
JQ|
XW|    # Fetch via Amazon PAAPI v5
NK|    #
VH|    # @param asin [String] Amazon ASIN
TM|    # @return [Hash] Product details
VQ|    def fetch_via_paapi(asin)
NX|      paapi_service = Scraper::AmazonPaapiService.new
HT|      data = paapi_service.fetch_product(asin)

VN|      format_result(
JN|        title: data[:title],
RJ|        description: data[:description],
KK|        images: data[:images],
QV|        variants: [],  # PAAPI doesn't provide detailed variants
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
MK|      data[:attributes][:source] = 'amazon'
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
JQ|    # Check if Amazon PAAPI is configured
NK|    #
VH|    # @return [Boolean] PAAPI configured?
TM|    def amazon_paapi_configured?
RJ|      access_key = Rails.application.credentials.dig(:amazon, :access_key)
NK|      secret_key = Rails.application.credentials.dig(:amazon, :secret_key)
NK|      partner_tag = Rails.application.credentials.dig(:amazon, :partner_tag)
NK|      access_key.present? && secret_key.present? && partner_tag.present?
PT|    end
PT|  end
PT|end
