# frozen_string_literal: true

# Job to overlay translated text on product images
# Queued after TranslationJob completes
class ImageOverlayJob < ApplicationJob
  queue_as :default

  # Perform image overlay for translated text
  #
  # @param extraction_run_id [String, Integer] ID of the ExtractionRun
  def perform(extraction_run_id)
    extraction_run = ExtractionRun.find(extraction_run_id)
    source_product = extraction_run.source_product

    # Get translated data
    translation_run = extraction_run.translation_run
    return unless translation_run&.completed?

    translated_images = translation_run.translated_data || []
    return if translated_images.empty?

    # Process each image with overlay
    processed_images = translated_images.map do |image_data|
      process_image_overlay(image_data, translation_run)
    end

    # Store processed images in source_product
    source_product.update!(
      processed_images: processed_images,
      status: :ready
    )

    Rails.logger.info "Image overlay completed for extraction_run #{extraction_run_id}"
  rescue StandardError => e
    extraction_run&.update(status: :failed)
    Rails.logger.error "Image overlay failed: #{e.message}"
    raise
  end

  private

  def process_image_overlay(image_data, translation_run)
    original_image_url = image_data[:image_url]
    translated_text = image_data[:translated_text]
    original_text = image_data[:original_text]

    return nil if original_image_url.blank? || translated_text.blank?

    # Determine overlay position based on original text region
    # For now, use a simple approach - this could be enhanced with OCR region data
    overlay_data = [
      {
        text: translated_text,
        position: 'bottom-left',
        style: {
          font_size: 16,
          font: 'sans',
          color: 'white',
          bg_color: 'black',
          bg_alpha: 0.7,
          padding: 5
        }
      }
    ]

    # Create overlay service
    overlay_service = Image::OverlayService.new(
      image_url: original_image_url,
      overlay_data: overlay_data,
      options: {
        output_format: 'png',
        quality: 90
      }
    )

    # Generate overlay image
    base64_image = overlay_service.overlay

    # In production, upload to S3 or cloud storage
    # For now, store base64 data
    {
      image_index: image_data[:image_index],
      original_image_url: original_image_url,
      processed_image_data: base64_image,
      overlay_text: translated_text,
      timestamp: Time.current.iso8601
    }
  rescue StandardError => e
    Rails.logger.error "Failed to process overlay for image #{image_data[:image_index]}: #{e.message}"

    # Return original image data on error
    {
      image_index: image_data[:image_index],
      original_image_url: original_image_url,
      error: e.message
    }
  end
end
