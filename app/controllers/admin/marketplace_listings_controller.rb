# frozen_string_literal: true

module Admin
  class MarketplaceListingsController < Admin::BaseController
    # layout 'admin'
    # allow_unauthenticated_access
    # before_action :require_basic_auth
    before_action :set_listing, only: [:show, :edit, :update, :destroy]

    def index
      @listings = Current.account ? Current.account.marketplace_listings : MarketplaceListing.all

      # 필터링
      if params[:search].present?
        search_term = "%#{params[:search]}%"
        catalog_products = CatalogProduct.where(
          'translated_title ILIKE ? OR translated_description ILIKE ?',
          search_term, search_term
        )
        @listings = @listings.where(catalog_product: catalog_products)
      end

      if params[:marketplace].present?
        @listings = @listings.where(marketplace: params[:marketplace])
      end

      if params[:status].present?
        @listings = @listings.where(status: params[:status])
      end

      # 페이지네이션
      @listings = @listings.order(created_at: :desc).page(params[:page] || 1).per(20)
    end

    def show
      # @listing is set by before_action
    end

    def new
      @listing = Current.account ? Current.account.marketplace_listings.build : MarketplaceListing.new
      if params[:catalog_product_id].present?
        @listing.catalog_product = Current.account ? Current.account.catalog_products.find_by(id: params[:catalog_product_id]) : CatalogProduct.find_by(id: params[:catalog_product_id])
      end
    end

    def edit
      # @listing is set by before_action
    end

    def create
      @listing = Current.account ? Current.account.marketplace_listings.build(listing_params) : MarketplaceListing.new(listing_params)

      if @listing.save
        # 리스팅 발행 작업 큐잉
        PublishListingJob.perform_later(@listing.id)

        redirect_to admin_marketplace_listing_path(@listing), notice: '리스팅이 생성되었습니다. 발행 처리 중입니다.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @listing.update(listing_params)
        redirect_to admin_marketplace_listing_path(@listing), notice: '리스팅이 업데이트되었습니다.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @listing.destroy
      redirect_to admin_marketplace_listings_path, notice: '리스팅이 삭제되었습니다.'
    end

    private

    def set_listing
      @listing = Current.account ? Current.account.marketplace_listings.find(params[:id]) : MarketplaceListing.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_marketplace_listings_path, alert: '리스팅을 찾을 수 없습니다.'
    end

    def listing_params
      params.require(:marketplace_listing).permit(
        :catalog_product_id,
        :marketplace,
        :marketplace_category_id,
        :marketplace_category_code,
        :listing_price_krw,
        :stock_quantity,
        :status
      )
    end
  end
end
