# frozen_string_literal: true

# Job to create CatalogProduct from processed SourceProduct data
# Queued after ImageOverlayJob completes
class CreateCatalogProductJob < ApplicationJob
  queue_as :default

  # Perform catalog product creation
  #
  # @param source_product_id [String, Integer] ID of the SourceProduct
  def perform(source_product_id)
    source_product = SourceProduct.find(source_product_id)

    # Verify all processing is complete
    return unless source_product.status == 'ready'

    # Get translation data
    extraction_run = source_product.extraction_runs.order(created_at: :desc).first
    return unless extraction_run&.translation_run&.completed?

    translation_run = extraction_run.translation_run

    # Calculate pricing (FX conversion + markup)
    pricing = calculate_pricing(source_product)

    # Create catalog product
    catalog_product = CatalogProduct.create!(
      account: source_product.account,
      source_product: source_product,
      translated_title: extract_translated_title(translation_run),
      translated_description: extract_translated_description(translation_run),
      base_price_krw: pricing[:base_price_krw],
      cost_price_krw: pricing[:cost_price_krw],
      margin_percent: pricing[:margin_percent],
      status: :draft,
      kc_cert_status: :unknown,
      processed_images: source_product.processed_images || [],
      original_images: source_product.original_images || [],
      variants: source_product.original_variants || [],
      attributes: source_product.original_attributes || {},
      specifications: source_product.specifications || {},
      risk_flags: {}
    )

    Rails.logger.info "Catalog product created: #{catalog_product.id} from source_product #{source_product_id}"
  rescue StandardError => e
    source_product&.update(status: :failed)
    Rails.logger.error "Failed to create catalog product: #{e.message}"
    raise
  end

  private

  def extract_translated_title(translation_run)
    # Use the first translated text as title for now
    # In production, this would be extracted from the translation metadata
    source_product = translation_run.extraction_run.source_product

    # Try to find translated title in translation data
    translated_data = translation_run.translated_data || []
    return translated_data.first&.dig(:translated_text) if translated_data.any?

    # Fallback: translate title on the fly
    source_lang = detect_source_language(source_product.source_platform)
    service = Translation::PapagoService.new(
      source_lang: source_lang,
      target_lang: 'ko',
      options: { source_text: source_product.original_title }
    )

    result = service.translate
    result[:translated_text]
  end

  def extract_translated_description(translation_run)
    # Extract translated description
    # In production, this would be extracted from the translation metadata
    source_product = translation_run.extraction_run.source_product
    source_product.original_description
  end

  def calculate_pricing(source_product)
    # Get latest FX rate
    fx_rate = FxRateSnapshot.latest_rate(source_product.original_currency)
    raise "No FX rate available for #{source_product.original_currency}" unless fx_rate

    # Convert to KRW
    original_krw = source_product.original_price_cents * fx_rate.rate

    # Apply cost markup (e.g., 1.2x for shipping/fees)
    cost_krw = (original_krw * 1.2).to_i

    # Apply profit margin (e.g., 30%)
    base_price_krw = (cost_krw * 1.3).to_i

    # Calculate margin percentage
    margin_percent = ((base_price_krw - cost_krw).to_f / base_price_krw * 100).round(2)

    {
      cost_price_krw: cost_krw,
      base_price_krw: base_price_krw,
      margin_percent: margin_percent
    }
  end

  def detect_source_language(platform)
    case platform.to_sym
    when :taobao, :tmall, :aliexpress
      'zh-CN'
    when :amazon
      'en'
    else
      'en'
    end
  end
end
