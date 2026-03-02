# frozen_string_literal: true

# Job to fetch detailed product information from source platform
# Queued by SourcingOrchestrator when SourceProduct is created
class FetchProductDetailsJob < ApplicationJob
  queue_as :default

  # Perform product details fetch
  #
  # @param source_product_id [String, Integer] ID of the SourceProduct
  def perform(source_product_id)
    source_product = SourceProduct.find(source_product_id)

    # Choose scraper based on platform
    scraper = choose_scraper(source_product.source_platform)

    # Fetch product details
    product_details = scraper.fetch_product(source_product.source_url)

    # Update source product with detailed information
    source_product.update!(
      original_description: product_details[:description],
      original_variants: product_details[:variants] || [],
      original_attributes: product_details[:attributes] || {},
      original_images: product_details[:images] || source_product.original_images,
      specifications: product_details[:specifications] || {},
      shipping_info: product_details[:shipping] || {},
      stock_info: product_details[:stock] || {}
    )

    Rails.logger.info "Product details fetched for source_product #{source_product_id}"
  rescue StandardError => e
    source_product&.update(status: :failed)
    Rails.logger.error "Failed to fetch product details: #{e.message}"
    raise
  end

  private

  SB|  def choose_scraper(platform)
VK|    case platform.to_sym
ZM|    when :taobao
NJ|      Scraper::TaobaoScraperService.new
ZV|    when :tmall
TW|      Scraper::TmallScraperService.new
KV|    when :aliexpress
NZ|      Scraper::AliexpressScraperService.new
JS|    when :amazon
PS|      Scraper::AmazonScraperService.new
SQ|    when :ali_1688
JT|      # 1688 uses AliExpress-style scraping (no public API)
NZ|      Scraper::AliexpressScraperService.new
SQ|    else
JT|      # Default to Taobao scraper
NJ|      Scraper::TaobaoScraperService.new
PT|    end
PT|  end
end
