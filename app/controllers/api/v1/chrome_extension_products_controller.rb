# frozen_string_literal: true

module Api
  module V1
    class ChromeExtensionProductsController < BaseController
      # Extract product from Chrome Extension
      # Content Script에서 호출하여 상품 데이터 저장
      def extract
        product_data = extract_params

        # Validate required fields
        required_fields = [:platform, :source_id, :title, :price, :currency]
        missing_fields = required_fields.select { |field| product_data[field].blank? }
        return render_error(
          code: "VALIDATION_FAILED",
          message: "Missing required fields: #{missing_fields.join(', ')}",
          status: :unprocessable_entity
        ) if missing_fields.any?

        # Map platform to enum
        platform_enum = map_platform(product_data[:platform])
        return render_error(
          code: "INVALID_PLATFORM",
          message: "Invalid platform: #{product_data[:platform]}",
          status: :unprocessable_entity
        ) if platform_enum.blank?

        # Check if product already exists
        existing_product = current_account_relation(SourceProduct).find_by(
          source_platform: platform_enum,
          source_id: product_data[:source_id]
        )

        if existing_product
          # Update existing product
          update_source_product!(existing_product, product_data)
          render_success(data: serialize_source_product(existing_product))
        else
          # Create new product
          new_product = create_source_product!(product_data, platform_enum)
          render_success(data: serialize_source_product(new_product), status: :created)
        end
      end

      # Get recent products
      # Chrome Extension popup에서 최근 상품 목록 표시
      def index
        scope = current_account_relation(SourceProduct)
        scope = scope.where(status: :ready) if params[:status].present?
        scope = scope.where(source_platform: params[:platform]) if params[:platform].present?

        # Cursor-based pagination
        products, meta = cursor_paginate(scope, order_column: :collected_at)

        render_success(
          data: products.map { |p| serialize_source_product(p) },
          meta: meta
        )
      end

      # Get product details
      def show
        product = current_account_relation(SourceProduct).find(params[:id])
        render_success(data: serialize_source_product(product, detailed: true))
      end

      # Get product statistics
      # Chrome Extension popup에서 통계 표시
      def stats
        stats = {
          total: current_account_relation(SourceProduct).count,
          pending: current_account_relation(SourceProduct).where(status: :pending).count,
          ready: current_account_relation(SourceProduct).where(status: :ready).count,
          failed: current_account_relation(SourceProduct).where(status: :failed).count,
          listed: current_account_relation(CatalogProduct).where(status: :listed).count
        }

        # Platform breakdown
        stats[:by_platform] = SourceProduct
          .where(account_id: Current.account.id)
          .group(:source_platform)
          .count
          .transform_keys { |k| k.to_s }

        render_success(data: stats)
      end

      # Update product metadata
      def update
        product = current_account_relation(SourceProduct).find(params[:id])
        product.update!(update_params)

        render_success(data: serialize_source_product(product))
      end

      # Delete product
      def destroy
        product = current_account_relation(SourceProduct).find(params[:id])
        product.destroy!

        render_success(data: { deleted: true })
      end

      private

      # Strong parameters for product extraction
      def extract_params
        params.permit(
          :platform,
          :source_id,
          :title,
          :price,
          :currency,
          :url,
          :description,
          :shop_name,
          images: [],
          variants: [],
          specifications: {},
          collected_at: :datetime
        )
      end

      # Strong parameters for product update
      def update_params
        params.permit(
          :title,
          :price,
          :currency,
          :description,
          :shop_name,
          :status,
          images: [],
          variants: [],
          specifications: {}
        )
      end

      # Map platform string to enum value
      def map_platform(platform_string)
        mapping = {
          'taobao' => :taobao,
          'tmall' => :tmall,
          'aliexpress' => :aliexpress,
          'amazon' => :amazon,
          'amazon_jp' => :amazon,
          '1688' => :taobao
        }

        mapping[platform_string&.downcase]
      end

      # Create source product
      def create_source_product!(data, platform_enum)
        current_account_relation(SourceProduct).create!(
          source_platform: platform_enum,
          source_id: data[:source_id],
          source_url: data[:url] || build_source_url(data[:platform], data[:source_id]),
          original_title: data[:title],
          original_price_cents: convert_to_cents(data[:price]),
          original_currency: data[:currency],
          original_description: data[:description],
          shop_name: data[:shop_name],
          images: Array(data[:images]),
          variants_data: data[:variants] || [],
          specifications: data[:specifications] || {},
          collected_at: data[:collected_at] || Time.current,
          status: :pending
        )
      end

      # Update source product
      def update_source_product!(product, data)
        product.update!(
          original_title: data[:title],
          original_price_cents: convert_to_cents(data[:price]),
          original_currency: data[:currency],
          original_description: data[:description],
          shop_name: data[:shop_name],
          images: Array(data[:images]),
          variants_data: data[:variants] || [],
          specifications: data[:specifications] || {},
          collected_at: data[:collected_at] || Time.current
        )
      end

      # Build source URL
      def build_source_url(platform, source_id)
        case platform&.downcase
        when 'taobao', 'tmall', '1688'
          "https://item.taobao.com/item.htm?id=#{source_id}"
        when 'aliexpress'
          "https://www.aliexpress.com/item/#{source_id}.html"
        when 'amazon', 'amazon_jp'
          "https://www.amazon.com/dp/#{source_id}"
        else
          ""
        end
      end

      # Convert price to cents
      def convert_to_cents(price)
        return 0 if price.blank?

        # Handle different number formats
        price_str = price.to_s.gsub(/[^0-9.,]/, '')
        price_float = price_str.to_f

        (price_float * 100).to_i
      end

      # Serialize source product for API response
      def serialize_source_product(product, detailed: false)
        serialized = {
          id: product.id,
          platform: product.source_platform.to_s,
          source_id: product.source_id,
          title: product.original_title,
          price: product.original_price_cents.to_f / 100,
          currency: product.original_currency,
          url: product.source_url,
          shop_name: product.shop_name,
          images: Array(product.images).first(detailed ? 10 : 1),
          status: product.status.to_s,
          collected_at: product.collected_at&.iso8601,
          created_at: product.created_at&.iso8601
        }

        # Include catalog product info if available
        if product.catalog_product.present?
          serialized[:catalog_product] = {
            id: product.catalog_product.id,
            translated_title: product.catalog_product.translated_title,
            base_price_krw: product.catalog_product.base_price_krw,
            status: product.catalog_product.status.to_s
          }
        end

        # Include details if requested
        if detailed
          serialized.merge!({
            description: product.original_description,
            variants: product.variants_data,
            specifications: product.specifications,
            all_images: Array(product.images)
          })
        end

        serialized
      end
    end
  end
end
