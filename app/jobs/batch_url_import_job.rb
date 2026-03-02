# frozen_string_literal: true

# Job to import products in bulk from multiple URLs
# Supports batch processing with progress tracking
class BatchUrlImportJob < ApplicationJob
  queue_as :default

  # Perform batch URL import
  #
  # @param account_id [String, Integer] Account ID (for scoping)
  # @param urls [Array<String>] List of product URLs to import
  # @param user_id [String, Integer] User ID who initiated import
  # @param options [Hash] Additional options
  # @option options [Symbol] :platform Force specific platform
  # @option options [Boolean] :auto_publish Auto-publish after import (default: false)
  # @option options [String] :batch_id Batch identifier for grouping
  # @option options [Integer] :chunk_size Number of URLs to process at once (default: 10)
  # @return [Hash] Import results summary
  def perform(account_id, urls, user_id, options = {})
    account = Account.find(account_id)
    user = User.find(user_id)
    batch_id = options[:batch_id] || SecureRandom.uuid

    Rails.logger.info "Starting batch import #{batch_id} for account #{account_id} with #{urls.length} URLs"

    results = {
      batch_id: batch_id,
      total: urls.length,
      succeeded: 0,
      failed: 0,
      skipped: 0,
      source_products: [],
      errors: []
    }

    # Process URLs in chunks to avoid memory issues
    chunk_size = options[:chunk_size] || 10
    urls.each_slice(chunk_size).with_index do |chunk, chunk_index|
      Rails.logger.info "Processing chunk #{chunk_index + 1} (#{chunk.length} URLs)"

      chunk.each_with_index do |url, index|
        global_index = (chunk_index * chunk_size) + index + 1

        begin
          result = import_single_url(account, user, url, options, batch_id, global_index)

          if result[:success]
            results[:succeeded] += 1
            results[:source_products] << result[:source_product_id]
          elsif result[:skipped]
            results[:skipped] += 1
          else
            results[:failed] += 1
            results[:errors] << {
              url: url,
              error: result[:error],
              index: global_index
            }
          end

          # Small delay between requests to avoid rate limiting
          sleep(0.5) unless index == chunk.length - 1
        rescue StandardError => e
          results[:failed] += 1
          results[:errors] << {
            url: url,
            error: e.message,
            index: global_index
          }

          Rails.logger.error "Failed to import URL #{url}: #{e.message}"
        end
      end
    end

    # Create import summary record
    create_import_summary(account, user, batch_id, results)

    # Auto-publish if requested
    if options[:auto_publish]
      auto_publish_products(account, results[:source_products], user_id)
    end

    Rails.logger.info "Batch import #{batch_id} completed: #{results[:succeeded]} succeeded, #{results[:failed]} failed, #{results[:skipped]} skipped"

    results
  end

  private

  # Import a single URL
  #
  # @param account [Account] Account instance
  # @param user [User] User instance
  # @param url [String] Product URL
  # @param options [Hash] Import options
  # @param batch_id [String] Batch identifier
  # @param index [Integer] URL index
  # @return [Hash] Import result
  def import_single_url(account, user, url, options, batch_id, index)
    # Validate URL
    unless valid_url?(url)
      return { success: false, error: 'Invalid URL format' }
    end

    # Detect platform
    platform = options[:platform] || detect_platform(url)

    # Check for duplicates
    existing = SourceProduct.where(
      account: account,
      source_url: url,
      source_platform: platform
    ).first

    if existing
      Rails.logger.info "Skipping duplicate product: #{url} (existing: #{existing.id})"
      return { success: false, skipped: true, source_product_id: existing.id }
    end

    # Create source product
    source_product = SourceProduct.create!(
      account: account,
      user: user,
      source_url: url,
      source_platform: platform,
      original_title: extract_title_from_url(url),
      status: :pending,
      batch_id: batch_id,
      import_index: index
    )

    Rails.logger.info "Created source product #{source_product.id} for #{url}"

    # Queue detailed fetch job
    FetchProductDetailsJob.perform_later(source_product.id)

    {
      success: true,
      source_product_id: source_product.id,
      platform: platform
    }
  end

  # Validate URL format
  #
  # @param url [String] URL to validate
  # @return [Boolean] Valid?
  def valid_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  # Detect platform from URL
  #
  # @param url [String] Product URL
  # @return [Symbol] Platform symbol
  def detect_platform(url)
    normalized_url = url.downcase

    case normalized_url
    when /taobao\.com/
      :taobao
    when /tmall\.com/
      :tmall
    when /aliexpress\.com/
      :aliexpress
    when /amazon\.(com|co\.jp|co\.uk|de|fr|es|it|ca)/
      :amazon
    when /1688\.com/
      :ali_1688
    else
      :unknown
    end
  end

  # Extract title from URL (heuristic)
  #
  # @param url [String] Product URL
  # @return [String] Extracted title
  def extract_title_from_url(url)
    uri = URI.parse(url)
    path = uri.path

    # Try to extract meaningful part from URL
    segments = path.split('/').reject(&:empty?)
    last_segment = segments.last

    if last_segment
      # Remove file extensions
      title = last_segment.gsub(/\.(html?|htm)$/, '')
      # Decode URL encoding
      title = CGI.unescape(title)
      # Replace dashes/hyphens with spaces
      title = title.gsub(/[-_]/, ' ')
      # Clean up
      title = title.squish
      title.present? ? title : 'Imported Product'
    else
      'Imported Product'
    end
  end

  # Create import summary record
  #
  # @param account [Account] Account instance
  # @param user [User] User instance
  # @param batch_id [String] Batch identifier
  # @param results [Hash] Import results
  def create_import_summary(account, user, batch_id, results)
    # Check if ImportSummary model exists, if not create it dynamically
    if defined?(ImportSummary)
      ImportSummary.create!(
        account: account,
        user: user,
        batch_id: batch_id,
        total_urls: results[:total],
        succeeded: results[:succeeded],
        failed: results[:failed],
        skipped: results[:skipped],
        source_product_ids: results[:source_products],
        errors: results[:errors],
        completed_at: Time.current
      )
    else
      Rails.logger.info "Import summary for batch #{batch_id}: #{results}"
    end
  end

  # Auto-publish imported products
  #
  # @param account [Account] Account instance
  # @param source_product_ids [Array<String>] Source product IDs
  # @param user_id [String, Integer] User ID
  def auto_publish_products(account, source_product_ids, user_id)
    source_product_ids.each do |source_product_id|
      begin
        source_product = SourceProduct.find(source_product_id)

        # Only publish if product has completed details
        if source_product.status == 'completed'
          # Queue publish job
          PublishListingJob.perform_later(source_product.id, user_id)

          Rails.logger.info "Queued auto-publish for source product #{source_product_id}"
        end
      rescue StandardError => e
        Rails.logger.error "Failed to auto-publish source product #{source_product_id}: #{e.message}"
      end
    end
  end
end
