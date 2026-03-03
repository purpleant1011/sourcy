# frozen_string_literal: true

module Admin
  class SettlementsController < Admin::BaseController
    def index
      @orders = Current.account ? Current.account.orders : Order.all

      # 마켓플레이스 필터
      if params[:marketplace].present?
        @orders = @orders.where(marketplace_platform: params[:marketplace])
      end

      # 상태 필터
      if params[:status].present?
        @orders = @orders.where(order_status: params[:status])
      end

      # 날짜 범위 필터
      if params[:start_date].present?
        @orders = @orders.where('ordered_at >= ?', params[:start_date])
      end

      if params[:end_date].present?
        @orders = @orders.where('ordered_at <= ?', Date.parse(params[:end_date]).end_of_day)
      end

      # 정산 요약
      @summary = {
        total_count: @orders.count,
        total_amount: @orders.sum(:total_amount_krw),
        by_platform: @orders.group(:marketplace_platform).count
      }

      page = (params[:page] || 1).to_i
      @pagy, @orders = pagy(@orders.order(ordered_at: :desc), limit: 50, page: page)
    end

    def show
      @order = Current.account ? Current.account.orders.find(params[:id]) : Order.find(params[:id])
      @items = @order.order_items.includes(:catalog_product)
      @shipment = @order.shipments.order(created_at: :desc).first
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_settlements_path, alert: '주문을 찾을 수 없습니다.'
    end

    def report
      @start_date = params[:start_date] || 30.days.ago.to_date
      @end_date   = params[:end_date] || Date.current
      @orders = Current.account ? Current.account.orders : Order.all
      @orders = @orders.where(ordered_at: @start_date..@end_date.to_date.end_of_day)
      @total   = @orders.sum(:total_amount_krw)
      @count   = @orders.count
    end
  end
end
