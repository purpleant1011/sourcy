# frozen_string_literal: true

# Job to extract text from product images using OCR
# Queued by SourcingOrchestrator after FetchProductDetailsJob
class OcrExtractionJob < ApplicationJob
  queue_as :default

  # Perform OCR extraction on all images for a given extraction run
  #
  # @param extraction_run_id [String, Integer] ID of the ExtractionRun
  def perform(extraction_run_id)
    extraction_run = ExtractionRun.find(extraction_run_id)

    # Find source product
    source_product = extraction_run.source_product

    # Get all images from source product
    images = source_product.original_images || []
    return if images.empty?

    # Process each image with OCR
    extracted_data = images.map.with_index do |image_url, index|
      process_image(image_url, index, extraction_run, source_product)
    end

    # Update extraction run with extracted data
    extraction_run.update!(
      extracted_text_data: extracted_data,
      status: :completed,
      completed_at: Time.current
    )

    Rails.logger.info "OCR extraction completed for extraction_run #{extraction_run_id}"
  rescue StandardError => e
    extraction_run&.update(status: :failed)
    Rails.logger.error "OCR extraction failed: #{e.message}"
    raise
  end

  private

  def process_image(image_url, index, extraction_run, source_product)
    # Detect language from source platform
    language = detect_language(source_product.source_platform)

    # Choose OCR provider
    ocr_service = choose_ocr_service(extraction_run, image_url, language)

    # Extract text
    result = ocr_service.extract_text

    {
      image_index: index,
      image_url: image_url,
      extracted_text: result[:text],
      confidence: result[:confidence],
      regions: result[:regions],
      provider: result[:provider],
      timestamp: result[:timestamp]
    }
  rescue StandardError => e
    Rails.logger.error "Failed to process image #{index}: #{e.message}"

    # Return error data for this image
    {
      image_index: index,
      image_url: image_url,
      error: e.message,
      extracted_text: "",
      confidence: 0.0,
      regions: []
    }
  end

  def detect_language(platform)
    case platform.to_sym
    when :taobao, :tmall, :aliexpress
      'zh-CN' # Simplified Chinese
    when :amazon
      'en-US' # English
    else
      'en-US'
    end
  end

  def choose_ocr_service(extraction_run, image_url, language)
    provider = extraction_run.provider

    case provider.to_sym
    when :gpt
      # For GPT-based OCR, we'll use a stub or integrate with GPT Vision API
      Ocr::GoogleVisionService.new(image_url: image_url, options: { language: language })
    when :claude
      # Claude Vision for OCR
      Ocr::NaverClovaService.new(image_url: image_url, options: { language: language })
    when :gemini
      Ocr::GoogleVisionService.new(image_url: image_url, options: { language: language })
    else
      # Default to Naver Clova for Korean optimization
      Ocr::NaverClovaService.new(image_url: image_url, options: { language: language })
    end
  end
end
