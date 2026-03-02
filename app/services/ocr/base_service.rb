# frozen_string_literal: true

# Base OCR service for text extraction from images
# Subclasses must implement the #extract_text method
module Ocr
  class BaseService
    class ExtractionError < StandardError; end

    attr_reader :image_url, :options

    # Initialize OCR service
    #
    # @param image_url [String] URL of the image to process
    # @param options [Hash] Additional options
    # @option options [String] :language ISO language code (e.g., 'zh-CN', 'en-US')
    # @option options [Boolean] :detect_text Whether to detect text (default: true)
    def initialize(image_url:, options: {})
      @image_url = image_url
      @options = options
    end

    # Extract text from the image
    #
    # @abstract
    # @return [Hash] Extracted data including text, confidence, and bounding boxes
    # @raise [NotImplementedError] if subclass doesn't implement
    def extract_text
      raise NotImplementedError, "Subclasses must implement #extract_text"
    end

    # Check if the service is available
    #
    # @return [Boolean] true if API credentials are configured
    def available?
      credentials_configured?
    end

    protected

    # Download image and return file path
    #
    # @return [String, nil] Path to downloaded file
    def download_image
      return nil unless @image_url.present?

      response = HTTParty.get(@image_url, timeout: 30, follow_redirects: true)
      return nil unless response.success?

      # Create temp file
      temp_file = Tempfile.new(['ocr_', File.extname(@image_url)])
      temp_file.binmode
      temp_file.write(response.body)
      temp_file.close

      temp_file.path
    rescue StandardError => e
      Rails.logger.error "Failed to download image: #{e.message}"
      nil
    end

    # Clean up temp file
    #
    # @param file_path [String] Path to temp file
    def cleanup_temp_file(file_path)
      File.delete(file_path) if file_path && File.exist?(file_path)
    rescue StandardError => e
      Rails.logger.warn "Failed to cleanup temp file: #{e.message}"
    end

    # Format OCR result to standard structure
    #
    # @param text [String] Extracted text
    # @param confidence [Float] Confidence score (0-1)
    # @param regions [Array<Hash>] Text regions with bounding boxes
    # @return [Hash] Formatted result
    def format_result(text:, confidence: 0.0, regions: [])
      {
        text: text.to_s.strip,
        confidence: confidence.to_f,
        regions: regions,
        provider: self.class.name.demodulize,
        timestamp: Time.current.iso8601
      }
    end

    # Check if API credentials are configured
    #
    # @abstract
    # @return [Boolean]
    def credentials_configured?
      raise NotImplementedError, "Subclasses must implement #credentials_configured?"
    end
  end
end
