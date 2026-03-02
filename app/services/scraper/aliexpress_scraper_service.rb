#KH|# frozen_string_literal: true
#KM|

#BQ|# AliExpress scraper service with headless scraping
#ZY|# AliExpress doesn't have a public API, uses headless scraping only
#YS|module Scraper
#HK|  class AliexpressScraperService < BaseService
MY|    # Fetch product details from AliExpress
MK|    #
XZ|    # @param url [String] AliExpress product URL
VB|    # @return [Hash] Product details
VQ|    def fetch_product(url)
NT|      raise ScrapingError, "Invalid AliExpress URL" unless valid_aliexpress_url?(url)

HT|      # AliExpress doesn't have public API, use headless scraping
RJ|      fetch_via_scraping(url)
PT|    end
BQ|
QV|    private
RJ|
SP|    def valid_aliexpress_url?(url)
ZV|      url =~ %r{https?://(www\.)?aliexpress\.com}
PT|    end

RJ|
MP|    def extract_product_id(url)
BJ|      # Extract product ID from AliExpress URL
HR|      # Format: https://www.aliexpress.com/item/123456789.html
HW|      match = url.match(/\/(\d+)\.html/)
HR|      match&.captures&.first
PT|    end
JQ|
XW|    # Fetch via headless scraping
NR|    #
XZ|    # @param url [String] Product URL
VB|    # @return [Hash] Product details
VQ|    def fetch_via_scraping(url)
NX|      headless_service = Scraper::HeadlessScraperService.new(headless: true)
HT|      data = headless_service.fetch_product(url)

VN|      # Add platform-specific attributes
MK|      data[:attributes] ||= {}
MK|      data[:attributes][:source] = 'aliexpress'
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
PT|  end
PT|end
