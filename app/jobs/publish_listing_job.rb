# frozen_string_literal: true

# Job to publish marketplace listing
# Queued when user publishes a MarketplaceListing
class PublishListingJob < ApplicationJob
  queue_as :bulk

  # Perform listing publish
  #
  # @param listing_id [String, Integer] ID of the MarketplaceListing
  def perform(listing_id)
    listing = MarketplaceListing.find(listing_id)

    # Verify listing is ready to publish
    return unless listing.status == 'draft'

    # Get marketplace adapter
    adapter = choose_adapter(listing.marketplace)

    # Publish listing
    result = adapter.publish(listing)

    # Update listing status
    if result[:success]
      listing.update!(
        status: :listed,
        marketplace_product_id: result[:marketplace_product_id],
        marketplace_url: result[:marketplace_url],
        published_at: Time.current
      )

      Rails.logger.info "Listing published: #{listing.id} to #{listing.marketplace}"
    else
      listing.update!(
        status: :failed,
        error_message: result[:error]
      )

      Rails.logger.error "Failed to publish listing #{listing.id}: #{result[:error]}"
    end
  end

  private

  def choose_adapter(marketplace)
    case marketplace.to_sym
    when :smart_store
      Marketplace::SmartStoreAdapter.new
    when :coupang
      Marketplace::CoupangAdapter.new
    when :gmarket
      Marketplace::GmarketAdapter.new
    when :elevenst
      Marketplace::ElevenstAdapter.new
    else
      raise "Unknown marketplace: #{marketplace}"
    end
  end
end
