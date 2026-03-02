# frozen_string_literal: true

# Job to process return requests
# Queued by webhooks or admin actions
class ProcessReturnRequestJob < ApplicationJob
  queue_as :default

  # Process a return request
  #
  # @param return_request_id [String, Integer] ID of the ReturnRequest
  # @param action [String] Action to perform (approve, reject, complete)
  # @param metadata [Hash] Additional metadata for the action
  def perform(return_request_id, action, metadata = {})
    return_request = ReturnRequest.find(return_request_id)

    case action.to_s.downcase
    when 'approve'
      approve_return(return_request, metadata)
    when 'reject'
      reject_return(return_request, metadata)
    when 'complete'
      complete_return(return_request, metadata)
    when 'cancel'
      cancel_return(return_request, metadata)
    else
      raise ArgumentError, "Unknown action: #{action}"
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Return request not found: #{return_request_id}"
  rescue StandardError => e
    Rails.logger.error "ProcessReturnRequestJob error: #{e.message}"
    raise
  end

  private

  # Approve a return request
  #
  # @param return_request [ReturnRequest] The return request to approve
  # @param metadata [Hash] Additional metadata
  def approve_return(return_request, metadata)
    # Check if return request is in pending status
    unless return_request.pending?
      Rails.logger.warn "Cannot approve return request #{return_request.id}: not in pending status"
      return
    end

    # Update return request status
    return_request.update!(
      status: :approved,
      approved_at: Time.current,
      approved_by: metadata[:approved_by],
      notes: metadata[:notes] || return_request.notes
    )

    # Use OrderProcessor to process the return
    processor = OrderProcessor.new(return_request.order)
    processor.process_return(
      reason: return_request.reason,
      metadata: {
        return_request_id: return_request.id,
        refund_amount: return_request.refund_amount
      }
    )

    Rails.logger.info "Return request approved: #{return_request.id}"

    # Create audit log
    AuditLog.create(
      account: return_request.account,
      action_type: 'update',
      entity_type: 'ReturnRequest',
      entity_id: return_request.id,
      details: {
        action: 'approve',
        approved_by: metadata[:approved_by],
        refund_amount: return_request.refund_amount,
        reason: return_request.reason
      }
    )

    # Notify marketplace of return approval
    notify_marketplace(return_request, :approved)
  end

  # Reject a return request
  #
  # @param return_request [ReturnRequest] The return request to reject
  # @param metadata [Hash] Additional metadata
  def reject_return(return_request, metadata)
    # Check if return request is in pending status
    unless return_request.pending?
      Rails.logger.warn "Cannot reject return request #{return_request.id}: not in pending status"
      return
    end

    # Update return request status
    return_request.update!(
      status: :rejected,
      rejected_at: Time.current,
      rejected_by: metadata[:rejected_by],
      notes: metadata[:notes] || return_request.notes
    )

    Rails.logger.info "Return request rejected: #{return_request.id}"

    # Create audit log
    AuditLog.create(
      account: return_request.account,
      action_type: 'update',
      entity_type: 'ReturnRequest',
      entity_id: return_request.id,
      details: {
        action: 'reject',
        rejected_by: metadata[:rejected_by],
        rejection_reason: metadata[:reason] || 'Not eligible for return',
        original_reason: return_request.reason
      }
    )

    # Notify marketplace of return rejection
    notify_marketplace(return_request, :rejected)
  end

  # Complete a return request
  #
  # @param return_request [ReturnRequest] The return request to complete
  # @param metadata [Hash] Additional metadata
  def complete_return(return_request, metadata)
    # Check if return request is in approved status
    unless return_request.approved?
      Rails.logger.warn "Cannot complete return request #{return_request.id}: not approved"
      return
    end

    # Update return request status
    return_request.update!(
      status: :completed,
      completed_at: Time.current,
      notes: metadata[:notes] || return_request.notes
    )

    # Mark order as returned
    order = return_request.order
    unless order.returned?
      order.update!(
        status: :returned,
        returned_at: Time.current
      )
    end

    Rails.logger.info "Return request completed: #{return_request.id}"

    # Create audit log
    AuditLog.create(
      account: return_request.account,
      action_type: 'update',
      entity_type: 'ReturnRequest',
      entity_id: return_request.id,
      details: {
        action: 'complete',
        order_id: order.id,
        refund_amount: return_request.refund_amount,
        actual_refund_amount: metadata[:actual_refund_amount]
      }
    )

    # Notify marketplace of return completion
    notify_marketplace(return_request, :completed)
  end

  # Cancel a return request
  #
  # @param return_request [ReturnRequest] The return request to cancel
  # @param metadata [Hash] Additional metadata
  def cancel_return(return_request, metadata)
    # Only pending returns can be cancelled
    unless return_request.pending?
      Rails.logger.warn "Cannot cancel return request #{return_request.id}: not in pending status"
      return
    end

    # Update return request status
    return_request.update!(
      status: :cancelled,
      cancelled_at: Time.current,
      notes: metadata[:notes] || return_request.notes
    )

    Rails.logger.info "Return request cancelled: #{return_request.id}"

    # Create audit log
    AuditLog.create(
      account: return_request.account,
      action_type: 'update',
      entity_type: 'ReturnRequest',
      entity_id: return_request.id,
      details: {
        action: 'cancel',
        cancelled_by: metadata[:cancelled_by],
        reason: metadata[:reason] || 'Return request cancelled'
      }
    )
  end

  # Notify marketplace of return request status change
  #
  # @param return_request [ReturnRequest] The return request
  # @param status [Symbol] The new status
  def notify_marketplace(return_request, status)
    order = return_request.order

    # Get marketplace adapter
    adapter = MarketplaceAdapter::BaseAdapter.instantiate(order.marketplace)

    if adapter && adapter.respond_to?(:notify_return_status)
      begin
        adapter.notify_return_status(
          order.marketplace_order_id,
          return_request.id,
          status,
          return_request: return_request
        )
        Rails.logger.info "Notified #{order.marketplace} of return #{status}"
      rescue StandardError => e
        Rails.logger.error "Failed to notify marketplace of return status: #{e.message}"
      end
    end
  end
end
