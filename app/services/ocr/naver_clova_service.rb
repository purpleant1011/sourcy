# frozen_string_literal: true

# Naver Clova OCR service using CLOVA Face Recognition API
# Requires NAVER_CLIENT_ID and NAVER_CLIENT_SECRET in Rails credentials
# @see https://api.ncloud-docs.com/docs/ai-naver-clova-ocr
module Ocr
  class NaverClovaService < BaseService
    class AuthenticationError < ExtractionError; end

    API_ENDPOINT = "https://kr.object.ncloudstorage.com/v2.0/appkeys"

    attr_reader :service_url

    # Initialize with image URL and options
    #
    # @param image_url [String] URL of the image to process
    # @param options [Hash] Additional options
    # @option options [String] :language Language code (e.g., 'ko', 'ja', 'zh-CN', 'en')
    # @option options [Boolean] :detect_document Whether to use document text detection
    def initialize(image_url:, options: {})
      super
      @language = options[:language] || 'ko'
      @detect_document = options[:detect_document] || true
      @service_url = determine_service_url
    end

    # Extract text using Naver Clova OCR API
    #
    # @return [Hash] Extracted text with confidence and regions
    def extract_text
      raise AuthenticationError, "Naver Clova credentials not configured" unless available?

      image_path = download_image
      raise ExtractionError, "Failed to download image" unless image_path

      begin
        result = perform_ocr(image_path)
        format_result_from_clova(result)
      ensure
        cleanup_temp_file(image_path)
      end
    end

    # Check if Naver credentials are configured
    #
    # @return [Boolean]
    def available?
      Rails.application.credentials.dig(:naver, :client_id).present? &&
        Rails.application.credentials.dig(:naver, :client_secret).present?
    end

    private

    def determine_service_url
      if @detect_document
        # Document text detection for full document text with layout
        "#{API_ENDPOINT}/general"
      else
        # Standard text detection
        "#{API_ENDPOINT}/credit-card"
      end
    end

    def perform_ocr(image_path)
      client_id = Rails.application.credentials.dig(:naver, :client_id)
      client_secret = Rails.application.credentials.dig(:naver, :client_secret)

      # Prepare request
      uri = URI(@service_url)

      # Clova OCR requires multipart/form-data with image file
      boundary = "----WebKitFormBoundary#{SecureRandom.hex(16)}"
      post_body = build_multipart_body(boundary, image_path)

      # Make API request
      response = HTTParty.post(
        uri.to_s,
        body: post_body,
        headers: {
          "X-OCR-SECRET" => client_secret,
          "Content-Type" => "multipart/form-data; boundary=#{boundary}"
        },
        timeout: 60
      )

      raise ExtractionError, "Clova OCR API error: #{response.code}" unless response.success?

      parse_clova_response(response.parsed_response)
    end

    def build_multipart_body(boundary, image_path)
      image_data = File.binread(image_path)

      body = "--#{boundary}\r\n"
      body += 'Content-Disposition: form-data; name="image"; filename="image.jpg"' + "\r\n"
      body += "Content-Type: image/jpeg\r\n\r\n"
      body += image_data + "\r\n"
      body += "--#{boundary}\r\n"

      # Add language parameter
      body += 'Content-Disposition: form-data; name="language"' + "\r\n\r\n"
      body += @language + "\r\n"
      body += "--#{boundary}--\r\n"

      body
    end

    def parse_clova_response(response)
      images = response.dig("images") || []
      return { text: "", confidence: 0.0, regions: [] } if images.empty?

      fields = images.first.dig("fields") || []

      regions = fields.map do |field|
        bounding_poly = field.dig("boundingPoly", "vertices") || []

        # Calculate bounding box from vertices
        x_values = bounding_poly.map { |v| v["x"].to_i }.compact
        y_values = bounding_poly.map { |v| v["y"].to_i }.compact

        {
          text: field.dig("inferText") || "",
          confidence: field.dig("inferConfidence", 0).to_f / 100,
          bounding_box: {
            x: x_values.min || 0,
            y: y_values.min || 0,
            width: (x_values.max - x_values.min) || 0,
            height: (y_values.max - y_values.min) || 0
          }
        }
      end

      # Combine all text (in reading order)
      full_text = regions.map { |r| r[:text] }.join(" ")

      {
        text: full_text,
        confidence: regions.empty? ? 0.0 : regions.map { |r| r[:confidence] }.sum / regions.size,
        regions: regions
      }
    end

    def format_result_from_clova(result)
      format_result(
        text: result[:text],
        confidence: result[:confidence],
        regions: result[:regions]
      )
    end
  end
end
