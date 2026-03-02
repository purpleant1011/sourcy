module Api
  module V1
    class CatalogProductsController < BaseController
      def index
        records, meta = cursor_paginate(current_account_relation(CatalogProduct), order_column: :created_at)
        render_success(data: records.as_json(include: :source_product), meta: meta)
      end

      def show
        catalog_product = current_account_relation(CatalogProduct).find(params[:id])
        render_success(data: catalog_product.as_json(include: %i[source_product marketplace_listings]))
      end

      def update
        catalog_product = current_account_relation(CatalogProduct).find(params[:id])
        catalog_product.update!(catalog_product_params)
        render_success(data: catalog_product.as_json)
      end

      def translate
        catalog_product = current_account_relation(CatalogProduct).find(params[:id])
        job_id = SecureRandom.uuid

        render_success(
          data: {
            job_id: job_id,
            catalog_product_id: catalog_product.id,
            status: "queued"
          },
          status: :accepted
        )
      end

      def bulk_translate
        catalog_product_ids = params.fetch(:catalog_product_ids, [])
        products = current_account_relation(CatalogProduct).where(id: catalog_product_ids)
        job_id = SecureRandom.uuid

        render_success(
          data: {
            job_id: job_id,
            status: "queued",
            total: products.count,
            catalog_product_ids: products.pluck(:id)
          },
          status: :accepted
        )
      end

      private

      def catalog_product_params
        params.require(:catalog_product).permit(
          :translated_title,
          :translated_description,
          :base_price_krw,
          :cost_price_krw,
          :margin_percent,
          :status,
          :kc_cert_required,
          :kc_cert_status,
          :hs_code,
          :customs_duty_rate,
          { processed_images: [] },
          { category_tags: [] },
          { risk_flags: {} }
        )
      end
    end
  end
end
