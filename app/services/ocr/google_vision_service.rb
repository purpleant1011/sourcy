# frozen_string_literal: true

# Google Cloud Vision API OCR service
# Requires GOOGLE_CLOUD_CREDENTIALS in Rails credentials
# @see https://cloud.google.com/vision/docs
module Ocr
  class GoogleVisionService < BaseService
    class AuthenticationError < ExtractionError; end

    # Initialize with image URL and options
    #
    # @param image_url [String] URL of the image to process
    # @param options [Hash] Additional options
    # @option options [String] :language ISO language code (e.g., 'zh-CN', 'ja', 'en')
    # @option options [Boolean] :detect_document Whether to use document text detection
    # @option options [Boolean] :dense_text Whether to use dense text detection
    def initialize(image_url:, options: {})
      super
      @language = options[:language]
      @detect_document = options[:detect_document] || true
    end

    # Extract text using Google Vision API
    #
    # @return [Hash] Extracted text with confidence and regions
    def extract_text
      raise AuthenticationError, "Google Cloud credentials not configured" unless available?

      image_path = download_image
      raise ExtractionError, "Failed to download image" unless image_path

      begin
        result = perform_ocr(image_path)
        format_result_from_google(result)
      ensure
        cleanup_temp_file(image_path)
      end
    end

    # Check if Google Cloud credentials are configured
    #
    # @return [Boolean]
    def available?
      Rails.application.credentials.dig(:google_cloud, :credentials).present?
    end

    private

    def perform_ocr(image_path)
      require 'google/cloud/vision'

      credentials_json = Rails.application.credentials.dig(:google_cloud, :credentials)
      vision = Google::Cloud::Vision.image_annotator(
        credentials: JSON.parse(credentials_json),
        project: Rails.application.credentials.dig(:google_cloud, :project_id)
      )

      image_content = File.binread(image_path)
      image = vision.image(image_content)

      if @detect_document
        # Document text detection for full document text with layout
        response = image.document_text_detection(language: @language)
        parse_document_response(response)
      else
        # Standard text detection
        response = image.text_detection(language: @language)
        parse_text_response(response)
      end
    end

    def parse_document_response(response)
      text_blocks = response.text_annotations[1..-1] || []

      regions = text_blocks.map do |block|
        vertices = block.bounding_poly.vertices

        {
          text: block.description,
          confidence: block.confidence.to_f / 100,
          bounding_box: {
            x: vertices[0].x,
            y: vertices[0].y,
            width: vertices[2].x - vertices[0].x,
            height: vertices[2].y - vertices[0].y
          }
        }
      end

      full_text = response.text_annotations.first&.description || ""

      {
        text: full_text,
        confidence: regions.empty? ? 0.0 : regions.map { |r| r[:confidence] }.sum / regions.size,
        regions: regions
      }
    end

    def parse_text_response(response)
      text_annotations = response.text_annotations[1..-1] || []

      regions = text_annotations.map do |annotation|
        vertices = annotation.bounding_poly.vertices

        {
          text: annotation.description,
          confidence: annotation.confidence.to_f / 100,
          bounding_box: {
            x: vertices[0].x,
            y: vertices[0].y,
            width: vertices[2].x - vertices[0].x,
            height: vertices[2].y - vertices[0].y
          }
        }
      end

      full_text = response.text_annotations.first&.description || ""

      {
        text: full_text,
        confidence: regions.empty? ? 0.0 : regions.map { |r| r[:confidence] }.sum / regions.size,
        regions: regions
      }
    end

    def format_result_from_google(result)
      format_result(
        text: result[:text],
        confidence: result[:confidence],
        regions: result[:regions]
      )
    end
  end
end
