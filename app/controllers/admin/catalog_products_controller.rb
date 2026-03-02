# frozen_string_literal: true

module Admin
  class CatalogProductsController < Admin::BaseController
    # layout 'admin'
    # allow_unauthenticated_access
    # before_action :require_basic_auth
    before_action :set_catalog_product, only: [:show, :edit, :update, :destroy]

    def index
      @catalog_products = Current.account ? Current.account.catalog_products : CatalogProduct.all

      # 필터링
      if params[:search].present?
        search_term = "%#{params[:search]}%"
        @catalog_products = @catalog_products.where(
          'translated_title ILIKE ? OR translated_description ILIKE ?',
          search_term, search_term
        )
      end

      if params[:status].present?
        @catalog_products = @catalog_products.where(status: params[:status])
      end

      # 페이지네이션 (cursor-based using pagy)
      @catalog_products = @catalog_products.order(created_at: :desc).page(params[:page] || 1).per(20)
    end

    def show
      # @catalog_product is set by before_action
    end

    def new
      @catalog_product = Current.account ? Current.account.catalog_products.build : CatalogProduct.new
    end

    def edit
      # @catalog_product is set by before_action
    end

    def create
      @catalog_product = Current.account ? Current.account.catalog_products.build(catalog_product_params) : CatalogProduct.new(catalog_product_params)

      if @catalog_product.save
        redirect_to admin_catalog_product_path(@catalog_product), notice: '제품이 생성되었습니다.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @catalog_product.update(catalog_product_params)
        redirect_to admin_catalog_product_path(@catalog_product), notice: '제품이 업데이트되었습니다.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @catalog_product.destroy
      redirect_to admin_catalog_products_path, notice: '제품이 삭제되었습니다.'
    end
    private

    def set_catalog_product
      @catalog_product = Current.account ? Current.account.catalog_products.find(params[:id]) : CatalogProduct.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_catalog_products_path, alert: '제품을 찾을 수 없습니다.'
    end

    def catalog_product_params
      params.require(:catalog_product).permit(
        :translated_title,
        :translated_description,
        :base_price_krw,
        :cost_price_krw,
        :margin_percent,
        :kc_cert_status,
        :kc_cert_required,
        :status,
        attributes: {},
        specifications: {},
        risk_flags: {}
      )
    end
  end
end
