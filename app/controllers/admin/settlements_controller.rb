# frozen_string_literal: true

module Admin
  class SettlementsController < Admin::BaseController
    # layout 'admin'
    # allow_unauthenticated_access
    # before_action :require_basic_auth
    before_action :set_settlement, only: [:show, :update, :verify]

    def index
      @settlements = Current.account ? Current.account.settlements.includes(:order) : Settlement.includes(:order)

      # 필터링
      if params[:marketplace].present?
        @settlements = @settlements.where(marketplace: params[:marketplace])
      end

      if params[:status].present?
        @settlements = @settlements.where(status: params[:status])
      end

      # 날짜 범위 필터링
      if params[:start_date].present?
        @settlements = @settlements.where('settlement_date >= ?', params[:start_date])
      end

      if params[:end_date].present?
        @settlements = @settlements.where('settlement_date <= ?', params[:end_date])
      end

      # 정렬
      @settlements = @settlements.order(settlement_date: :desc).page(params[:page] || 1).per(50)

      # 정산 요약
      @summary = calculate_summary(@settlements)
    end

    def show
      # @settlement is set by before_action
      @order = @settlement.order
    end

    def update
      status = params.dig(:settlement, :status)
      return render json: { success: false, error: 'Invalid status' } unless Settlement.statuses.include?(status)

      if @settlement.update(status: status)
        redirect_to admin_settlement_path(@settlement), notice: '정산 상태가 업데이트되었습니다.'
      else
        render :show, status: :unprocessable_entity
      end
    end

    def verify
      # Verify settlement amount
      calculator = OrderProcessing::SettlementCalculator.new(@settlement.order)
      calculation = calculator.calculate

      verification_result = {
        verified: false,
        calculated_net_amount: calculation[:net_amount],
        recorded_net_amount: @settlement.net_amount,
        difference: calculation[:net_amount] - @settlement.net_amount,
        tolerance: 0.01, # 1% 허용 오차
        within_tolerance: false
      }

      # Check if within 1% tolerance
      tolerance_amount = @settlement.net_amount * verification_result[:tolerance]
      verification_result[:within_tolerance] = verification_result[:difference].abs <= tolerance_amount
      verification_result[:verified] = verification_result[:within_tolerance]

      # Update settlement verification status
      @settlement.update(
        verified_at: Time.current,
        verification_passed: verification_result[:verified],
        verification_notes: verification_result[:within_tolerance] ? '1% 허용 오차 내 검증됨' : '허용 오차 초과'
      )

      render json: verification_result
    rescue StandardError => e
      render json: { verified: false, error: e.message }, status: :unprocessable_entity
    end

    def report
      start_date = params[:start_date] || 30.days.ago.to_date
      end_date = params[:end_date] || Date.current
      marketplace = params[:marketplace]

      # Generate settlement report
      report_data = CalculateSettlementJob.generate_report(
        account_id: Current.account&.id,
        start_date: start_date,
        end_date: end_date,
        marketplace: marketplace
      )

      @report = report_data
      @start_date = start_date
      @end_date = end_date
      @marketplace = marketplace
    end

    def export
      format = params[:format] || 'csv'

      case format
      when 'csv'
        export_csv
      when 'xlsx'
        export_xlsx
      else
        render json: { error: 'Unsupported format' }, status: :unprocessable_entity
      end
    end

    private

    def set_settlement
      @settlement = Current.account ? Current.account.settlements.find(params[:id]) : Settlement.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_settlements_path, alert: '정산을 찾을 수 없습니다.'
    end

    def settlement_params
      params.require(:settlement).permit(:status)
    end

    def calculate_summary(settlements)
      {
        total_count: settlements.count,
        total_gross: settlements.sum(:gross_amount),
        total_net: settlements.sum(:net_amount),
        total_fees: settlements.sum(:total_fees),
        total_taxes: settlements.sum(:total_taxes),
        by_status: settlements.group(:status).count,
        by_marketplace: settlements.group(:marketplace).sum(:net_amount)
      }
    end

    def export_csv
      require 'csv'

      settlements = Current.account ? Current.account.settlements : Settlement.all
      settlements = settlements.order(settlement_date: :desc).page(params[:page] || 1).per(1000)

      csv_data = CSV.generate(headers: true) do |csv|
        # CSV 헤더
        csv << [
          '정산 ID',
          '주문 ID',
          '마켓플레이스',
          '정산일',
          '총 금액',
          '수수료 합계',
          '세금 합계',
          '순수익',
          '상태'
        ]

        # CSV 데이터
        settlements.each do |settlement|
          csv << [
            settlement.id,
            settlement.order_id,
            settlement.marketplace,
            settlement.settlement_date,
            settlement.gross_amount,
            settlement.total_fees,
            settlement.total_taxes,
            settlement.net_amount,
            settlement.status
          ]
        end
      end

      send_data csv_data,
                filename: "settlements_#{Date.current}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    end

    def export_xlsx
      # Placeholder for Excel export
      # Would use gems like 'axlsx' or 'caxlsx' for actual implementation
      render json: { error: 'Excel export not implemented yet' }, status: :not_implemented
    end
  end
end
