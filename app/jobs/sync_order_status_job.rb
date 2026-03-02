# frozen_string_literal: true

# Job to sync order status from marketplace
# Queued by webhooks when marketplace sends order updates
class SyncOrderStatusJob < ApplicationJob
  queue_as :default

  # Perform order status sync
  #
  # @param order_id [String, Integer] ID of the Order
  # @param marketplace [String] Marketplace name
  # @param status [String] New status from marketplace
  # @param metadata [Hash] Additional metadata
  def perform(order_id, marketplace, status, metadata = {})
    order = Order.find(order_id)

    # Update order status
    order.update!(
      status: normalize_status(status),
      updated_at: Time.current
    )

    # Create tracking event if provided
    if metadata[:tracking_number].present?
      create_tracking_event(order, marketplace, metadata)
    end

    Rails.logger.info "Order status synced: #{order_id} to #{status}"
  rescue StandardError => e
    Rails.logger.error "Failed to sync order status: #{e.message}"
    raise
  end

  private

  def normalize_status(status)
    # Normalize marketplace status to our enum
    case status.to_s.downcase
    when 'pending', 'ordered', 'created'
      :pending
    when 'paid', 'confirmed'
      :confirmed
    when 'shipped', 'dispatched'
      :shipped
    when 'delivered'
      :delivered
    when 'cancelled', 'canceled'
      :cancelled
    when 'refunded'
      :refunded
    else
      :pending
    end
  end

  def create_tracking_event(order, marketplace, metadata)
    TrackingEvent.create!(
      order: order,
      marketplace: marketplace,
      event_type: 'status_update',
      event_code: metadata[:event_code] || 'UPDATE',
      description: metadata[:description] || "Status updated to #{metadata[:status]}",
      location: metadata[:location],
      tracking_number: metadata[:tracking_number],
      event_time: metadata[:event_time] || Time.current
    )
  end
end
