module Api
  module V1
    class AnalyticsController < BaseController
      def dashboard
        account = Current.account
        data = {
          source_products: account.source_products.count,
          catalog_products: account.catalog_products.count,
          listings_live: MarketplaceListing.joins(:catalog_product).where(catalog_products: { account_id: account.id }, status: :live).count,
          orders_open: account.orders.open_states.count,
          gross_revenue_krw: account.orders.sum(:total_amount_krw)
        }

        render_success(data: data)
      end

      def margin
        products = current_account_relation(CatalogProduct)
          .select(:id, :translated_title, :cost_price_krw, :base_price_krw, :margin_percent)
          .order(margin_percent: :desc)

        records, meta = cursor_paginate(products, order_column: :created_at)
        render_success(data: records.as_json, meta: meta)
      end
    end
  end
end
