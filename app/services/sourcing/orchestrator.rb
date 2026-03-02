# frozen_string_literal: true

# SourcingOrchestrator coordinates the entire product sourcing workflow:
# 1. Create SourceProduct from Chrome Extension data
# 2. Fetch detailed product info via scraping jobs
# 3. Extract text from images via OCR
# 4. Translate extracted text
# 5. Overlay translated text on images
# 6. Create CatalogProduct with processed data
#
# @see PRD Section 6.3 for the complete sourcing workflow
module Sourcing
  class Orchestrator
    include ActiveModel::Model

    attr_reader :account, :source_product, :errors

    # Initialize with account and source data from Chrome Extension
    #
    # @param account [Account] The account that owns the product
    # @param source_data [Hash] Product data from Chrome Extension
    # @option source_data [String] :url The product URL
    # @option source_data [String] :platform 'taobao', 'aliexpress', 'tmall', or 'amazon'
    # @option source_data [String] :product_id Unique product identifier from the platform
    # @option source_data [String] :title Original product title
    # @option source_data [String] :price Original price in source currency
    # @option source_data [String] :currency Original currency code (CNY, USD, etc.)
    # @option source_data [Array<Hash>] :images List of image URLs
    # @option source_data [Hash] :metadata Additional metadata (description, variants, etc.)
    def initialize(account:, source_data:)
      @account = account
      @source_data = source_data
      @errors = []
    end

    # Execute the complete sourcing workflow
    #
    # @return [Boolean] true if successful, false otherwise
    def call
      return false unless valid?

      ActiveRecord::Base.transaction do
        create_source_product
        create_extraction_run
        enqueue_jobs
        true
      end
    rescue StandardError => e
      @errors << e.message
      Rails.logger.error "SourcingOrchestrator failed: #{e.message}"
      false
    end

    # Get the created source product
    #
    # @return [SourceProduct, nil]
    def source_product
      @source_product
    end

    private

    def valid?
      validate_account!
      validate_source_data!
      @errors.empty?
    end

    def validate_account!
      @errors << "Account is required" unless @account.is_a?(Account)
    end

    def validate_source_data!
      @errors << "URL is required" unless @source_data[:url].present?
      @errors << "Platform is required" unless @source_data[:platform].present?
      @errors << "Product ID is required" unless @source_data[:product_id].present?
      @errors << "Title is required" unless @source_data[:title].present?
      @errors << "Price is required" unless @source_data[:price].present?
      @errors << "Currency is required" unless @source_data[:currency].present?
    end

    def create_source_product
      @source_product = SourceProduct.create!(
        account: @account,
        source_url: @source_data[:url],
        source_platform: @source_data[:platform],
        source_id: @source_data[:product_id],
        original_title: @source_data[:title],
        original_price_cents: parse_price(@source_data[:price]),
        original_currency: @source_data[:currency],
        original_description: @source_data[:metadata]&.dig(:description),
        original_images: @source_data[:images] || [],
        original_variants: @source_data[:metadata]&.dig(:variants) || [],
        original_attributes: @source_data[:metadata]&.dig(:attributes) || {},
        status: :pending
      )
    end

    def create_extraction_run
      @extraction_run = @source_product.extraction_runs.create!(
        input_hash: generate_input_hash,
        provider: Rails.application.credentials.dig(:ocr, :default_provider) || 'gpt',
        status: :pending
      )
    end

    def enqueue_jobs
      # Step 1: Fetch detailed product information
      FetchProductDetailsJob.perform_later(@source_product.id)

      # Step 2: Extract text from product images (after product details fetched)
      OcrExtractionJob.set(wait: 30.seconds).perform_later(@extraction_run.id)

      # Step 3: Translate extracted text (after OCR completes)
      # This job will enqueue multiple TranslationJob instances
      TranslationJob.set(wait: 60.seconds).perform_later(@extraction_run.id)

      # Step 4: Overlay translated text on images (after translation completes)
      ImageOverlayJob.set(wait: 90.seconds).perform_later(@extraction_run.id)

      # Step 5: Create CatalogProduct (after all processing completes)
      CreateCatalogProductJob.set(wait: 120.seconds).perform_later(@source_product.id)
    end

    def parse_price(price)
      return 0 unless price.present?

      # Remove currency symbols and commas, convert to cents
      price.to_s.gsub(/[^0-9.]/, '').to_f * 100
    end

    def generate_input_hash
      Digest::SHA256.hexdigest(@source_data.to_json)
    end
  end
end
