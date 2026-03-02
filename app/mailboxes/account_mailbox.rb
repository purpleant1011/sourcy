# frozen_string_literal: true

# Account email processing mailbox
# Handles account-related emails (order confirmations, notifications, etc.)
class AccountMailbox < ApplicationMailbox
  # Process incoming account emails
  def process
    # Route based on email subject/pattern
    case mail.subject.to_s
    when /주문확인|ORDER CONFIRMATION/
      process_order_confirmation
    when /배송알림|SHIPPING NOTIFICATION/
      process_shipping_notification
    when /반품요청|RETURN REQUEST/
      process_return_request
    when /결제완료|PAYMENT COMPLETED/
      process_payment_confirmation
    else
      log_unrecognized_email
    end
  end

  private

  def process_order_confirmation
    # Parse order confirmation from email body
    order_data = parse_order_confirmation

    if order_data[:order_number]
      # Update order status
      order = Order.find_by(marketplace_order_number: order_data[:order_number])
      order&.update(status: :confirmed)

      # Notify user
      OrderMailer.confirmation_email(order).deliver_later if order
    end
  end

  def process_shipping_notification
    # Parse shipping notification from email body
    shipping_data = parse_shipping_notification

    if shipping_data[:order_number] && shipping_data[:tracking_number]
      # Create or update shipment
      order = Order.find_by(marketplace_order_number: shipping_data[:order_number])
      return unless order

      shipment = order.shipments.find_or_create_by!(
        marketplace_tracking_number: shipping_data[:tracking_number]
      )

      shipment.update!(
        carrier: shipping_data[:carrier],
        status: :shipped,
        shipped_at: Time.current
      )

      # Start tracking job
      TrackShipmentJob.perform_later(shipment.id)

      # Notify user
      ShipmentMailer.shipping_notification(order, shipment).deliver_later
    end
  end

  def process_return_request
    # Parse return request from email body
    return_data = parse_return_request

    if return_data[:order_number]
      order = Order.find_by(marketplace_order_number: return_data[:order_number])
      return unless order

      # Create return request
      return_request = ReturnRequest.create!(
        order: order,
        reason: return_data[:reason],
        status: :pending,
        requested_at: Time.current
      )

      # Process return request asynchronously
      ProcessReturnRequestJob.perform_later(return_request.id)
    end
  end

  def process_payment_confirmation
    # Parse payment confirmation from email body
    payment_data = parse_payment_confirmation

    if payment_data[:order_number]
      order = Order.find_by(marketplace_order_number: payment_data[:order_number])
      order&.update(payment_status: :paid)
    end
  end

  def parse_order_confirmation
    # Parse order number, items, total from email body
    body = mail.decoded

    {
      order_number: body[/주문번호|Order Number[:\s]+([A-Z0-9]+)/i, 1],
      total: extract_amount(body),
      items: parse_items(body)
    }
  end

  def parse_shipping_notification
    # Parse shipping data from email body
    body = mail.decoded

    {
      order_number: body[/주문번호|Order Number[:\s]+([A-Z0-9]+)/i, 1],
      tracking_number: body[/운송장번호|Tracking Number[:\s]+([A-Z0-9]+)/i, 1],
      carrier: extract_carrier(body)
    }
  end

  def parse_return_request
    # Parse return request data from email body
    body = mail.decoded

    {
      order_number: body[/주문번호|Order Number[:\s]+([A-Z0-9]+)/i, 1],
      reason: body[/반품사유|Reason[:\s]+(.+)$/i, 1]
    }
  end

  def parse_payment_confirmation
    # Parse payment confirmation data from email body
    body = mail.decoded

    {
      order_number: body[/주문번호|Order Number[:\s]+([A-Z0-9]+)/i, 1],
      amount: extract_amount(body),
      payment_method: body[/결제수단|Payment Method[:\s]+(.+)$/i, 1]
    }
  end

  def extract_amount(text)
    # Extract amount like "₩50,000" or "$100.00"
    text.to_s[/[₩$￥€£]([\d,]+(?:\.\d{2})?)/, 1]
  end

  def extract_carrier(text)
    # Extract carrier name from text
    case text.upcase
    when /CJ대한통운|CJ LOGISTICS/
      :cj_logistics
    when /롯데|LOTTE/
      :lotte
    when /우체국|POST/
      :post_office
    else
      :other
    end
  end

  def parse_items(body)
    # Parse item list from email body
    # Simple implementation - can be enhanced with better parsing
    body.scan(/상품명|Item[:\s]+(.+?)(?=상품명|Item|$)/i).flatten
  end

  def log_unrecognized_email
    Rails.logger.info "Unrecognized account email from #{mail.from}: #{mail.subject}"
  end
end
