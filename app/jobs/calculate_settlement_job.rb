# frozen_string_literal: true

# Job to calculate and record settlements
# Queued on schedule or after order completion
class CalculateSettlementJob < ApplicationJob
  queue_as :default

  # Calculate settlement for a single order
  #
  # @param order_id [String, Integer] ID of the Order
  # @param force_recalculate [Boolean] Force recalculation even if settlement exists
  def perform(order_id, force_recalculate = false)
    order = Order.find(order_id)

    # Skip if order is not settled (delivered) or if settlement already exists
    return skip_order(order, '배송 완료되지 않음') unless order.delivered?
    return skip_order(order, '이미 정산됨') if order.settlement.present? && !force_recalculate

    # Calculate settlement using SettlementCalculator service
    calculator = OrderProcessing::SettlementCalculator.new(order)
    result = calculator.calculate

    # Create or update settlement record
    settlement = create_settlement(order, result)

    Rails.logger.info "Settlement calculated for order #{order.id}: #{settlement.net_amount}원"

    # Create audit log
    AuditLog.create(
      account: order.account,
      action_type: 'create',
      entity_type: 'Settlement',
      entity_id: settlement.id,
      details: {
        order_id: order.id,
        gross_amount: settlement.gross_amount,
        net_amount: settlement.net_amount,
        fees: settlement.total_fees,
        taxes: settlement.total_taxes,
        marketplace: order.marketplace
      }
    )

    settlement
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Order not found: #{order_id}"
  rescue StandardError => e
    Rails.logger.error "CalculateSettlementJob error: #{e.message}"
    raise
  end

  # Calculate settlements for multiple orders in batch
  #
  # @param account_id [String, Integer, nil] Optional account scope
  # @param start_date [Date] Start date for orders
  # @param end_date [Date] End date for orders
  # @param marketplace [String, nil] Optional marketplace filter
  def self.calculate_batch(account_id = nil, start_date: nil, end_date: nil, marketplace: nil)
    scope = Order.where(status: :delivered).where.missing(:settlement)

    scope = scope.where(account_id: account_id) if account_id
    scope = scope.where(marketplace: marketplace) if marketplace
    scope = scope.where('delivered_at >= ?', start_date) if start_date
    scope = scope.where('delivered_at <= ?', end_date) if end_date

    orders = scope.to_a

    Rails.logger.info "Calculating settlements for #{orders.size} orders..."

    results = {
      total: orders.size,
      succeeded: 0,
      failed: 0,
      settlements: []
    }

    orders.each do |order|
      begin
        settlement = new.perform(order.id)
        results[:succeeded] += 1
        results[:settlements] << settlement
      rescue StandardError => e
        results[:failed] += 1
        Rails.logger.error "Failed to calculate settlement for order #{order.id}: #{e.message}"
      end
    end

    Rails.logger.info "Batch settlement calculation complete: #{results[:succeeded]}/#{results[:total]} succeeded"

    results
  end

  # Generate settlement report for a period
  #
  # @param account_id [String, Integer, nil] Optional account scope
  # @param start_date [Date] Report start date
  # @param end_date [Date] Report end date
  # @param marketplace [String, nil] Optional marketplace filter
  def self.generate_report(account_id = nil, start_date:, end_date:, marketplace: nil)
    calculator = OrderProcessing::SettlementCalculator.new(nil)
    report = calculator.generate_report(
      account_id: account_id,
      start_date: start_date,
      end_date: end_date,
      marketplace: marketplace
    )

    # Create audit log for report generation
    AuditLog.create(
      account_id: account_id,
      action_type: 'report',
      entity_type: 'Settlement',
      entity_id: nil,
      details: {
        report_type: 'settlement_report',
        start_date: start_date,
        end_date: end_date,
        marketplace: marketplace,
        summary: report[:summary]
      }
    )

    report
  end

  private

  # Create settlement record from calculation result
  #
  # @param order [Order] The order to create settlement for
  # @param result [Hash] Calculation result from SettlementCalculator
  # @return [Settlement] Created settlement record
  def create_settlement(order, result)
    Settlement.create!(
      account: order.account,
      order: order,
      marketplace: order.marketplace,
      settlement_date: Date.current,
      gross_amount: result[:gross_amount],
      commission_fee: result[:commission_fee],
      payment_fee: result[:payment_fee],
      category_fee: result[:category_fee],
      additional_fee: result[:additional_fee],
      total_fees: result[:total_fees],
      vat: result[:vat],
      withholding_tax: result[:withholding_tax],
      total_taxes: result[:total_taxes],
      net_amount: result[:net_amount],
      currency: 'KRW',
      status: :pending,
      breakdown: result[:breakdown],
      metadata: {
        calculation_date: Time.current,
        order_details: {
          marketplace: order.marketplace,
          total_amount: order.total_amount
        }
      }
    )
  end

  # Skip calculation for ineligible orders
  #
  # @param order [Order] The order to skip
  # @param reason [String] Reason for skipping
  def skip_order(order, reason)
    Rails.logger.debug "Skipping settlement for order #{order.id}: #{reason}"
  end
end
