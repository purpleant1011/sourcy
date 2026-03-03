# frozen_string_literal: true

module Admin
  class OrdersController < Admin::BaseController
    before_action :set_order, only: [ :show, :update ]

    def index
      @orders = Current.account ? Current.account.orders : Order.all

      # 필터링
      if params[:search].present?
        search_term = "%#{params[:search]}%"
        @orders = @orders.where("external_order_id ILIKE ?", search_term)
      end

      if params[:status].present?
        @orders = @orders.where(order_status: params[:status])
      end

      # 날짜 범위 필터링
      if params[:date_range].present?
        case params[:date_range]
        when "7d"
          @orders = @orders.where("created_at >= ?", 7.days.ago)
        when "30d"
          @orders = @orders.where("created_at >= ?", 30.days.ago)
        when "90d"
          @orders = @orders.where("created_at >= ?", 90.days.ago)
        end
      end

      # 페이지네이션
      page = (params[:page] || 1).to_i
      @pagy, @orders = pagy(@orders.order(created_at: :desc), limit: 20, page: page)
    end

    def show
      # @order is set by before_action
      @items = @order.order_items.includes(:catalog_product)
      @shipment = @order.shipments.order(created_at: :desc).first
    end

    def update
      status = params.dig(:order, :order_status)
      unless status.present? && Order.order_statuses.key?(status)
        redirect_to admin_order_path(@order), alert: "유효하지 않은 상태입니다."
        return
      end

      if @order.update(order_status: status)
        redirect_to admin_order_path(@order), notice: "주문 상태가 업데이트되었습니다."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_order
      @order = Current.account ? Current.account.orders.find(params[:id]) : Order.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_orders_path, alert: "주문을 찾을 수 없습니다."
    end

    def order_params
      params.require(:order).permit(:order_status)
    end
  end
end
