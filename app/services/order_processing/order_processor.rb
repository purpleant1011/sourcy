# frozen_string_literal: true

# Order processing pipeline service
# Manages the entire order lifecycle from creation to completion
module OrderProcessing
  class OrderProcessor
    class ProcessingError < StandardError; end
    class ValidationError < StandardError; end
    class InsufficientStockError < ProcessingError; end

    # Initialize order processor
    #
    # @param order [Order] The order to process
    # @param account [Account] The account context
    def initialize(order, account = nil)
      @order = order
      @account = account || order.account
    end

    # Process order transition with validation
    #
    # @param new_status [Symbol] Target status
    # @param context [Hash] Additional context (payment_info, shipping_info, etc.)
    # @return [Hash] Result with success flag
    def process_transition(new_status, context = {})
      validate_transition!(new_status)

      case new_status
      when :confirmed
        process_confirmation(context)
      when :processing
        process_preparation(context)
      when :shipped
        process_shipment(context)
      when :delivered
        process_delivery(context)
      when :cancelled
        process_cancellation(context)
      when :returned
        process_return(context)
      else
        { success: false, error: "지원하지 않는 상태 전환: #{new_status}" }
      end
    rescue ValidationError => e
      log_transition_error(new_status, e.message)
      { success: false, error: e.message, error_type: :validation }
    rescue InsufficientStockError => e
      log_transition_error(new_status, e.message)
      { success: false, error: e.message, error_type: :insufficient_stock }
    rescue StandardError => e
      log_transition_error(new_status, e.message)
      { success: false, error: "주문 처리 중 오류 발생: #{e.message}", error_type: :internal }
    end

    # Confirm order (from pending)
    #
    # @param context [Hash] Payment and buyer information
    # @return [Hash] Processing result
    def process_confirmation(context = {})
      ApplicationRecord.transaction do
        # Validate payment
        unless context[:payment_status] == 'paid'
          return { success: false, error: '결제가 완료되지 않았습니다.' }
        end

        # Validate stock
        validate_stock!(@order)

        # Confirm order
        @order.update!(
          status: :confirmed,
          confirmed_at: Time.current,
          buyer_name: context[:buyer_name] || @order.buyer_name,
          buyer_phone: context[:buyer_phone] || @order.buyer_phone,
          buyer_email: context[:buyer_email] || @order.buyer_email,
          shipping_address: format_shipping_address(context),
          payment_method: context[:payment_method],
          payment_transaction_id: context[:payment_transaction_id]
        )

        # Deduct stock from catalog products
        deduct_stock!(@order)

        # Create audit log
        create_audit_log(:confirmed, { payment_method: context[:payment_method] })

        # Notify marketplace via adapter
        notify_marketplace(:confirmed) if context[:notify_marketplace]

        { success: true, status: 'confirmed' }
      end
    end

    # Prepare order for shipment (from confirmed)
    #
    # @param context [Hash] Packaging information
    # @return [Hash] Processing result
    def process_preparation(context = {})
      ApplicationRecord.transaction do
        # Update order status
        @order.update!(
          status: :processing,
          processing_started_at: Time.current,
          warehouse_location: context[:warehouse_location]
        )

        # Create or update shipment record
        shipment = create_or_update_shipment(context)

        # Create audit log
        create_audit_log(:processing, {
          warehouse_location: context[:warehouse_location],
          estimated_shipping_date: context[:estimated_shipping_date]
        })

        { success: true, status: 'processing', shipment_id: shipment.id }
      end
    end

    # Ship order (from processing)
    #
    # @param context [Hash] Shipping information
    # @return [Hash] Processing result
    def process_shipment(context = {})
      ApplicationRecord.transaction do
        shipment = @order.shipments.last

        unless shipment
          return { success: false, error: '배송 정보를 찾을 수 없습니다.' }
        end

        # Update shipment
        shipment.update!(
          carrier_code: context[:carrier_code],
          tracking_number: context[:tracking_number],
          shipped_at: Time.current,
          estimated_delivery_date: context[:estimated_delivery_date]
        )

        # Update order status
        @order.update!(
          status: :shipped,
          shipped_at: Time.current
        )

        # Add tracking event
        create_tracking_event(shipment, 'SHIPPED', '배송 시작됨', context)

        # Create audit log
        create_audit_log(:shipped, {
          carrier_code: context[:carrier_code],
          tracking_number: context[:tracking_number]
        })

        # Notify buyer
        notify_buyer(:shipped) if context[:notify_buyer]

        { success: true, status: 'shipped', shipment_id: shipment.id }
      end
    end

    # Mark order as delivered (from shipped)
    #
    # @param context [Hash] Delivery confirmation
    # @return [Hash] Processing result
    def process_delivery(context = {})
      ApplicationRecord.transaction do
        shipment = @order.shipments.last

        unless shipment
          return { success: false, error: '배송 정보를 찾을 수 없습니다.' }
        end

        # Update shipment
        shipment.update!(
          delivered_at: Time.current,
          actual_delivery_date: context[:actual_delivery_date] || Time.current
        )

        # Update order status
        @order.update!(
          status: :delivered,
          delivered_at: Time.current
        )

        # Add tracking event
        create_tracking_event(shipment, 'DELIVERED', '배송 완료됨', context)

        # Create settlement entry
        create_settlement_entry(:delivery, context)

        # Create audit log
        create_audit_log(:delivered, {
          actual_delivery_date: context[:actual_delivery_date]
        })

        # Notify buyer
        notify_buyer(:delivered) if context[:notify_buyer]

        { success: true, status: 'delivered' }
      end
    end

    # Cancel order
    #
    # @param context [Hash] Cancellation information
    # @return [Hash] Processing result
    def process_cancellation(context = {})
      ApplicationRecord.transaction do
        # Update order status
        @order.update!(
          status: :cancelled,
          cancelled_at: Time.current,
          cancellation_reason: context[:reason],
          cancellation_type: context[:type] || 'buyer_request'
        )

        # Restore stock if order was confirmed
        restore_stock!(@order) if @order.confirmed_at

        # Process refund if applicable
        process_refund!(context) if context[:refund_required]

        # Create audit log
        create_audit_log(:cancelled, {
          reason: context[:reason],
          type: context[:type],
          refund_required: context[:refund_required]
        })

        # Notify buyer
        notify_buyer(:cancelled) if context[:notify_buyer]

        { success: true, status: 'cancelled' }
      end
    end

    # Process return request
    #
    # @param context [Hash] Return information
    # @return [Hash] Processing result
    def process_return(context = {})
      ApplicationRecord.transaction do
        return_request = @order.return_request

        unless return_request
          return { success: false, error: '반품 요청을 찾을 수 없습니다.' }
        end

        # Update return request
        return_request.update!(
          status: :approved,
          approved_at: Time.current,
          approval_reason: context[:approval_reason]
        )

        # Update order status
        @order.update!(
          status: :returned,
          returned_at: Time.current
        )

        # Restore stock
        restore_stock!(@order)

        # Process refund
        process_refund!(context.merge(return_request_id: return_request.id))

        # Create settlement entry
        create_settlement_entry(:return, context)

        # Create audit log
        create_audit_log(:returned, {
          return_reason: context[:return_reason],
          refund_amount: context[:refund_amount]
        })

        { success: true, status: 'returned' }
      end
    end

    # Validate order before processing
    #
    # @param order [Order] The order to validate
    # @return [Hash] Validation result
    def self.validate_order(order)
      errors = []
      warnings = []

      # Check order has required fields
      errors << '구매자 이름이 필요합니다.' if order.buyer_name.blank?
      errors << '구매자 전화번호가 필요합니다.' if order.buyer_phone.blank?
      errors << '배송 주소가 필요합니다.' if order.shipping_address.blank?

      # Check order has items
      errors << '주문 상품이 없습니다.' if order.order_items.empty?

      # Check order has payment info
      errors << '결제 정보가 필요합니다.' if order.payment_method.blank?

      # Validate order items
      order.order_items.each do |item|
        errors << "상품 #{item.id}: 가격 정보가 없습니다." if item.unit_price_krw.zero?
        errors << "상품 #{item.id}: 수량이 0입니다." if item.quantity.zero?
      end

      # Check if order can be cancelled
      if order.status == 'delivered'
        errors << '이미 배송 완료된 주문은 취소할 수 없습니다.'
      end

      # Warnings
      warnings << '주문 생성 후 7일이 지난 경우 취소 수수료가 발생할 수 있습니다.' if order.created_at < 7.days.ago

      {
        valid: errors.empty?,
        errors:,
        warnings:
      }
    end

    # Calculate order total
    #
    # @param order [Order] The order
    # @return [Hash] Total breakdown
    def self.calculate_totals(order)
      items_total = order.order_items.sum { |item| item.unit_price_krw * item.quantity }
      shipping_fee = order.shipping_fee_krw || 0
      discount_amount = order.discount_amount_krw || 0
      vat = ((items_total + shipping_fee - discount_amount) * 0.1).to_i # 10% VAT

      {
        items_total:,
        shipping_fee:,
        discount_amount:,
        vat:,
        total: items_total + shipping_fee - discount_amount + vat
      }
    end

    private

    # Validate status transition
    #
    # @param new_status [Symbol] Target status
    # @raise [ValidationError] if transition is invalid
    def validate_transition!(new_status)
      current = @order.status.to_sym

      valid_transitions = {
        pending: [:confirmed, :cancelled],
        confirmed: [:processing, :cancelled],
        processing: [:shipped, :cancelled],
        shipped: [:delivered, :cancelled],
        delivered: [:returned],
        cancelled: [],
        returned: []
      }

      unless valid_transitions[current]&.include?(new_status)
        raise ValidationError, "잘못된 상태 전환: #{current} -> #{new_status}"
      end
    end

    # Validate and check stock
    #
    # @param order [Order] The order
    # @raise [InsufficientStockError] if stock is insufficient
    def validate_stock!(order)
      order.order_items.each do |item|
        listing = item.marketplace_listing
        catalog_product = listing.catalog_product

        if catalog_product.stock_quantity < item.quantity
          raise InsufficientStockError,
                "제품 '#{catalog_product.translated_title}'의 재고가 부족합니다. (필요: #{item.quantity}, 재고: #{catalog_product.stock_quantity})"
        end
      end
    end

    # Deduct stock from catalog products
    #
    # @param order [Order] The order
    def deduct_stock!(order)
      order.order_items.each do |item|
        listing = item.marketplace_listing
        catalog_product = listing.catalog_product

        catalog_product.update!(
          stock_quantity: catalog_product.stock_quantity - item.quantity,
          sold_quantity: catalog_product.sold_quantity + item.quantity
        )

        listing.update!(
          stock_quantity: listing.stock_quantity - item.quantity,
          sold_count: listing.sold_count + 1
        )
      end
    end

    # Restore stock when order is cancelled
    #
    # @param order [Order] The order
    def restore_stock!(order)
      order.order_items.each do |item|
        listing = item.marketplace_listing
        catalog_product = listing.catalog_product

        catalog_product.update!(
          stock_quantity: catalog_product.stock_quantity + item.quantity,
          sold_quantity: catalog_product.sold_quantity - item.quantity
        )

        listing.update!(
          stock_quantity: listing.stock_quantity + item.quantity,
          sold_count: listing.sold_count - 1
        )
      end
    end

    # Create or update shipment record
    #
    # @param context [Hash] Shipment context
    # @return [Shipment] Created or updated shipment
    def create_or_update_shipment(context)
      shipment = @order.shipments.find_or_initialize_by(marketplace: @order.marketplace)

      shipment.assign_attributes(
        carrier_code: context[:carrier_code] || 'UNKNOWN',
        tracking_number: context[:tracking_number] || '',
        warehouse_location: context[:warehouse_location],
        estimated_shipping_date: context[:estimated_shipping_date],
        estimated_delivery_date: context[:estimated_delivery_date],
        notes: context[:notes]
      )

      shipment.save!
      shipment
    end

    # Create tracking event
    #
    # @param shipment [Shipment] The shipment
    # @param status [String] Event status
    # @param description [String] Event description
    # @param context [Hash] Additional context
    def create_tracking_event(shipment, status, description, context = {})
      shipment.tracking_events.create!(
        status_code: status,
        status_description: description,
        location: context[:location] || '',
        event_timestamp: Time.current,
        raw_data: context.except(:location)
      )
    end

    # Process refund
    #
    # @param context [Hash] Refund information
    def process_refund!(context)
      @order.update!(
        refund_status: :processing,
        refund_amount_krw: context[:refund_amount] || @order.total_amount_krw,
        refund_requested_at: Time.current,
        refund_reason: context[:reason]
      )

      # Use payment gateway to process refund
      # This would integrate with PortOne API
      Rails.logger.info "Refund requested for order #{@order.id}: #{context[:refund_amount]} KRW"
    end

    # Create settlement entry
    #
    # @param type [Symbol] Settlement type (:delivery, :return, :cancel)
    # @param context [Hash] Additional context
    def create_settlement_entry(type, context = {})
      case type
      when :delivery
        amount = @order.net_amount_krw
      when :return, :cancel
        amount = -(@order.net_amount_krw || 0)
      else
        return
      end

      Settlement.create!(
        account: @account,
        marketplace: @order.marketplace,
        order: @order,
        settlement_type: type,
        amount_krw: amount,
        settlement_date: Time.current,
        status: :pending,
        details: context.except(:actual_delivery_date)
      )
    end

    # Format shipping address
    #
    # @param context [Hash] Shipping address context
    # @return [Hash] Formatted address
    def format_shipping_address(context)
      {
        recipient: context[:recipient] || @order.buyer_name,
        phone: context[:phone] || @order.buyer_phone,
        postal_code: context[:postal_code] || '',
        address1: context[:address1] || '',
        address2: context[:address2] || '',
        city: context[:city] || '',
        province: context[:province] || '',
        country: context[:country] || 'KR'
      }
    end

    # Create audit log entry
    #
    # @param action_type [Symbol] Action type
    # @param details [Hash] Additional details
    def create_audit_log(action_type, details = {})
      AuditLog.create(
        account: @account,
        action_type:,
        entity_type: 'Order',
        entity_id: @order.id,
        details: {
          order_number: @order.order_number,
          marketplace: @order.marketplace,
          status: @order.status,
          **details
        }
      )
    end

    # Notify marketplace via adapter
    #
    # @param action [Symbol] Action to notify
    def notify_marketplace(action)
      adapter = Marketplace::BaseAdapter.instantiate(@order.marketplace)
      return unless adapter

      case action
      when :confirmed
        result = adapter.sync_order(@order)
        Rails.logger.info "Marketplace sync result: #{result}"
      end
    rescue StandardError => e
      Rails.logger.error "Failed to notify marketplace: #{e.message}"
    end

    # Notify buyer
    #
    # @param action [Symbol] Notification type
    def notify_buyer(action)
      # TODO: Implement buyer notification (email, SMS, etc.)
      Rails.logger.info "Buyer notification queued: #{action} for order #{@order.id}"
    end

    # Log transition error
    #
    # @param new_status [Symbol] Target status
    # @param error_message [String] Error message
    def log_transition_error(new_status, error_message)
      Rails.logger.error "Order transition failed: #{@order.id} (#{@order.status} -> #{new_status}): #{error_message}"
      AuditLog.create(
        account: @account,
        action_type: 'error',
        entity_type: 'Order',
        entity_id: @order.id,
        details: {
          from_status: @order.status,
          to_status: new_status,
          error_message:
        }
      )
    end
  end
end
