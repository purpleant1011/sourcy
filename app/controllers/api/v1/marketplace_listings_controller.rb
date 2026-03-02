module Api
  module V1
    class MarketplaceListingsController < BaseController
      def index
        records, meta = cursor_paginate(scoped_listings, order_column: :created_at)
        render_success(data: records.as_json(include: %i[catalog_product listing_variants marketplace_account]), meta: meta)
      end

      def show
        listing = scoped_listings.find(params[:id])
        render_success(data: listing.as_json(include: %i[catalog_product listing_variants marketplace_account]))
      end

      def create
        listing = scoped_listings.new(marketplace_listing_params)
        return if ensure_account_access!(listing)

        listing.save!

        render_success(data: listing.as_json, status: :created)
      end

      def update
        listing = scoped_listings.find(params[:id])
        listing.update!(marketplace_listing_params)
        render_success(data: listing.as_json)
      end

      def destroy
        listing = scoped_listings.find(params[:id])
        listing.destroy!
        render_success(data: { deleted: true, id: listing.id })
      end

      def publish
        listing = scoped_listings.find(params[:id])
        listing.update!(status: :live, listed_at: Time.current)

        render_success(data: { id: listing.id, status: listing.status, listed_at: listing.listed_at })
      end

      def bulk_publish
        listings = scoped_listings.where(id: params.fetch(:listing_ids, []))
        published_ids = []

        listings.find_each do |listing|
          listing.update!(status: :live, listed_at: Time.current)
          published_ids << listing.id
        end

        render_success(data: { published_count: published_ids.size, listing_ids: published_ids })
      end

      def validate
        listing = scoped_listings.find(params[:id])
        errors = []
        errors << "listed_price_krw must be greater than 0" if listing.listed_price_krw.to_i <= 0
        errors << "marketplace_category_code is required" if listing.marketplace_category_code.blank?

        render_success(
          data: {
            id: listing.id,
            valid: errors.empty?,
            errors: errors
          }
        )
      end

      private

      def scoped_listings
        MarketplaceListing.joins(:catalog_product).where(catalog_products: { account_id: Current.account.id })
      end

      def marketplace_listing_params
        params.require(:marketplace_listing).permit(
          :catalog_product_id,
          :marketplace_account_id,
          :listed_price_krw,
          :marketplace_category_code,
          :status,
          :external_listing_id,
          :listed_at,
          :last_synced_at,
          { marketplace_attributes: {} },
          { sync_errors: [] }
        )
      end

      def ensure_account_access!(listing)
        return false if listing.catalog_product&.account_id == Current.account.id && listing.marketplace_account&.account_id == Current.account.id

        render_error(code: "FORBIDDEN", message: "Cross-account access denied", status: :forbidden)
        true
      end
    end
  end
end
