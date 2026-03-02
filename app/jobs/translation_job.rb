# frozen_string_literal: true

# Job to translate extracted text
# Queued after OcrExtractionJob completes
class TranslationJob < ApplicationJob
  queue_as :default

  # Perform translation on extracted text from OCR
  #
  # @param extraction_run_id [String, Integer] ID of the ExtractionRun
  def perform(extraction_run_id)
    extraction_run = ExtractionRun.find(extraction_run_id)
    source_product = extraction_run.source_product
    account = source_product.account

    # Get extracted OCR data
    extracted_data = extraction_run.extracted_text_data || []
    return if extracted_data.empty?

    # Get source and target languages
    source_lang = detect_source_language(source_product.source_platform)
    target_lang = 'ko' # Always translate to Korean

    # Get translation provider from account settings or default
    provider = determine_provider(extraction_run, account)

    # Translate product title first
    translated_title = translate_text(
      source_product.original_title,
      source_lang,
      target_lang,
      provider
    )

    # Translate product description
    translated_description = nil
    if source_product.original_description.present?
      translated_description = translate_text(
        source_product.original_description,
        source_lang,
        target_lang,
        provider
      )
    end

    # Translate extracted text from images
    translated_images = extracted_data.map do |image_data|
      next if image_data[:error].present? || image_data[:extracted_text].blank?

      translated = translate_text(
        image_data[:extracted_text],
        source_lang,
        target_lang,
        provider
      )

      {
        image_index: image_data[:image_index],
        image_url: image_data[:image_url],
        original_text: image_data[:extracted_text],
        translated_text: translated[:translated_text],
        confidence: translated[:confidence]
      }
    end.compact

    # Create translation run record
    translation_run = extraction_run.translation_runs.create!(
      provider: provider,
      source_lang: source_lang,
      target_lang: target_lang,
      input_text: extracted_data.map { |d| d[:extracted_text] }.join("\n"),
      input_hash: generate_input_hash(extracted_data),
      translated_data: translated_images,
      status: :completed,
      completed_at: Time.current
    )

    # Update extraction run with translation results
    extraction_run.update!(
      translation_run_id: translation_run.id,
      status: :completed
    )

    Rails.logger.info "Translation completed for extraction_run #{extraction_run_id}"
  rescue StandardError => e
    extraction_run&.update(status: :failed)
    Rails.logger.error "Translation failed: #{e.message}"
    raise
  end

  private

  def translate_text(text, source_lang, target_lang, provider)
    case provider.to_sym
    when :gpt
      service = Translation::GptService.new(
        source_lang: source_lang,
        target_lang: target_lang,
        options: {
          source_text: text,
          context: 'ecommerce',
          model: 'gpt-4o',
          temperature: 0.3
        }
      )
    when :deepl
      # DeepL service
      service = Translation::PapagoService.new(
        source_lang: source_lang,
        target_lang: target_lang,
        options: { source_text: text }
      )
    when :papago
      service = Translation::PapagoService.new(
        source_lang: source_lang,
        target_lang: target_lang,
        options: { source_text: text }
      )
    else
      # Default to Papago
      service = Translation::PapagoService.new(
        source_lang: source_lang,
        target_lang: target_lang,
        options: { source_text: text }
      )
    end

    service.translate
  end

  def detect_source_language(platform)
    case platform.to_sym
    when :taobao, :tmall, :aliexpress
      'zh-CN'
    when :amazon
      'en'
    when :gmarket
      'ko'
    else
      'en'
    end
  end

  def determine_provider(extraction_run, account)
    # Check if extraction run specifies a provider
    return extraction_run.provider if extraction_run.provider.present?

    # Check account preferences
    # For now, default to papago (Naver) for Korean translation
    'papago'
  end

  def generate_input_hash(data)
    Digest::SHA256.hexdigest(data.to_json)
  end
end
