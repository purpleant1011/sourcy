# frozen_string_literal: true

# Job to track shipments periodically
# Queued on schedule to track active shipments
class TrackShipmentJob < ApplicationJob
  queue_as :default

  # Track a single shipment
  #
  # @param shipment_id [String, Integer] ID of the Shipment
  # @param force_refresh [Boolean] Force refresh even if recently updated
  def perform(shipment_id, force_refresh = false)
    shipment = Shipment.find(shipment_id)

    # Skip if shipment is delivered, cancelled, or has no tracking number
    return skip_shipment(shipment, '완료된 배송') if shipment.delivered?
    return skip_shipment(shipment, '취소된 배송') if shipment.cancelled?
    return skip_shipment(shipment, '운송장 번호 없음') if shipment.tracking_number.blank?

    # Track shipment using ShipmentTracking service
    tracker = OrderProcessing::ShipmentTracking.new(shipment)
    result = tracker.track(force_refresh)

    if result[:success]
      Rails.logger.info "Shipment tracked: #{shipment.id}, Status: #{result[:status]}"
    else
      Rails.logger.error "Failed to track shipment #{shipment.id}: #{result[:error]}"

      # Create audit log for tracking failure
      AuditLog.create(
        account: shipment.account,
        action_type: 'error',
        entity_type: 'Shipment',
        entity_id: shipment.id,
        details: {
          action: 'track_shipment',
          error: result[:error],
          tracking_number: shipment.tracking_number
        }
      )
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Shipment not found: #{shipment_id}"
  rescue StandardError => e
    Rails.logger.error "TrackShipmentJob error: #{e.message}"
    raise
  end

  # Track all active shipments in batch
  #
  # @param account_id [String, Integer, nil] Optional account scope
  # @param limit [Integer] Maximum number of shipments to track
  def self.track_all(account_id = nil, limit: 100)
    scope = Shipment.active.where.not(tracking_number: nil)
    scope = scope.where(account_id: account_id) if account_id

    shipments = scope.limit(limit).to_a

    Rails.logger.info "Tracking #{shipments.size} shipments..."

    results = OrderProcessing::ShipmentTracking.track_batch(shipments)

    Rails.logger.info "Batch tracking complete: #{results[:succeeded]}/#{results[:total]} succeeded"

    results
  end

  private

  # Skip tracking for completed shipments
  #
  # @param shipment [Shipment] The shipment to skip
  # @param reason [String] Reason for skipping
  def skip_shipment(shipment, reason)
    Rails.logger.debug "Skipping shipment #{shipment.id}: #{reason}"
  end
end
