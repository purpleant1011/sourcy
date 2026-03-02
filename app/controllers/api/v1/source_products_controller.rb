module Api
  module V1
    class SourceProductsController < BaseController
      def index
        records, meta = cursor_paginate(current_account_relation(SourceProduct), order_column: :created_at)
        render_success(data: records.as_json, meta: meta)
      end

      def create
        source_product = current_account_relation(SourceProduct).new(source_product_params)
        source_product.collected_at ||= Time.current
        source_product.save!
        trigger_orchestrator(source_product)

        render_success(data: source_product.as_json, status: :created)
      end

      def show
        source_product = current_account_relation(SourceProduct).find(params[:id])
        render_success(data: source_product.as_json(include: :catalog_product))
      end

      def bulk_import
        products = params.fetch(:products, [])
        imported = []
        failed = []

        products.each_with_index do |raw_product, index|
          product_attrs = ActionController::Parameters.new(raw_product).permit(*source_product_permitted_attributes)
          source_product = current_account_relation(SourceProduct).new(product_attrs)
          source_product.collected_at ||= Time.current

          if source_product.save
            trigger_orchestrator(source_product)
            imported << source_product
          else
            failed << { index: index, errors: source_product.errors.to_hash }
          end
        end

        render_success(
          data: {
            imported_count: imported.size,
            failed_count: failed.size,
            imported: imported.as_json,
            failed: failed
          }
        )
      end

      private

      def source_product_params
        params.require(:source_product).permit(*source_product_permitted_attributes)
      end

      def source_product_permitted_attributes
        [
          :source_platform,
          :source_url,
          :source_id,
          :original_title,
          :original_description,
          :original_currency,
          :original_price_cents,
          :status,
          :collected_at,
          { original_images: [] },
          { raw_data: {} }
        ]
      end

      def trigger_orchestrator(source_product)
        return unless defined?(SourcingOrchestrator)

        SourcingOrchestrator.call(source_product: source_product)
      rescue StandardError
        nil
      end
    end
  end
end
