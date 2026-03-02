# frozen_string_literal: true

# Shipment tracking service
# Tracks shipments across multiple carriers and updates order status
module OrderProcessing
  class ShipmentTracking
    class TrackingError < StandardError; end
    class CarrierNotFoundError < TrackingError; end

    # Carrier configuration with tracking APIs
    CARRIERS = {
      # Domestic carriers (Korea)
      'CJ' => {
        name: 'CJ대한통운',
        tracking_url: 'https://www.cjlogistics.com/tracking/{tracking_number}',
        api_type: :api,
        api_url: 'https://www.cjlogistics.com/api/parcel/v1/tracking'
      },
      'LOTTE' => {
        name: '롯데택배',
        tracking_url: 'https://www.lotte.co.kr/homeshopping/tracking/tracking.do?InvNo={tracking_number}',
        api_type: :scrape,
        scrape_url: 'https://www.lotte.co.kr/homeshopping/tracking/tracking.do?InvNo={tracking_number}'
      },
      'HANJIN' => {
        name: '한진택배',
        tracking_url: 'https://www.hanjin.com/kor/Customer/DeliveryCargoTrace.do?wblnum={tracking_number}',
        api_type: :scrape,
        scrape_url: 'https://www.hanjin.com/kor/Customer/DeliveryCargoTrace.do?wblnum={tracking_number}'
      },
      'POST' => {
        name: '우체국',
        tracking_url: 'https://www.koreapost.go.kr/trace/Search.jsp?barcodeNo={tracking_number}',
        api_type: :scrape,
        scrape_url: 'https://www.koreapost.go.kr/trace/Search.jsp?barcodeNo={tracking_number}'
      },
      # International carriers
      'UPS' => {
        name: 'UPS',
        tracking_url: 'https://www.ups.com/track?loc=en_KR&tracknum={tracking_number}',
        api_type: :api,
        api_url: 'https://onlinetools.ups.com/track/v1/details'
      },
      'FEDEX' => {
        name: 'FedEx',
        tracking_url: 'https://www.fedex.com/ko-kr/tracking.html?tracknumbers={tracking_number}',
        api_type: :api,
        api_url: 'https://www.fedex.com/trackingCal/track'
      },
      'DHL' => {
        name: 'DHL',
        tracking_url: 'https://www.dhl.com/kr-kr/home/tracking/tracking-shipment?tracking-id={tracking_number}',
        api_type: :api,
        api_url: 'https://api.dhl.com/track/shipments'
      }
    }.freeze

    # Tracking status codes
    STATUS_MAP = {
      # Common status codes
      'ORDER_RECEIVED' => :picked_up,
      'PICKED_UP' => :picked_up,
      'IN_TRANSIT' => :in_transit,
      'OUT_FOR_DELIVERY' => :out_for_delivery,
      'DELIVERED' => :delivered,
      'DELIVERY_ATTEMPTED' => :delivery_attempted,
      'EXCEPTION' => :exception,
      'RETURNED' => :returned,
      'CANCELLED' => :cancelled
    }.freeze

    # Initialize tracking service
    #
    # @param shipment [Shipment] The shipment to track
    def initialize(shipment)
      @shipment = shipment
      @carrier = CARRIERS[shipment.carrier_code]

      raise CarrierNotFoundError, "지원하지 않는 배송사: #{shipment.carrier_code}" unless @carrier
    end

    # Track shipment and update tracking events
    #
    # @param force_refresh [Boolean] Force refresh even if recently updated
    # @return [Hash] Tracking result with latest status
    def track(force_refresh = false)
      return { success: false, error: '운송장 번호가 없습니다.' } unless @shipment.tracking_number.present?

      # Check if recently updated (within 30 minutes)
      unless force_refresh || @shipment.last_tracked_at.nil? || @shipment.last_tracked_at < 30.minutes.ago
        return { success: true, status: @shipment.delivery_status, recently_updated: true }
      end

      begin
        # Fetch tracking data based on carrier type
        tracking_data = if @carrier[:api_type] == :api
                        fetch_from_api
                      else
                        fetch_from_scrape
                      end

        return { success: false, error: '추적 정보를 가져올 수 없습니다.' } unless tracking_data

        # Process tracking events
        latest_status = process_tracking_events(tracking_data)

        # Update shipment
        @shipment.update!(
          delivery_status: latest_status,
          current_location: tracking_data[:current_location],
          estimated_delivery_date: tracking_data[:estimated_delivery],
          last_tracked_at: Time.current,
          tracking_data: tracking_data[:raw_data]
        )

        # Update order status if applicable
        update_order_status!(latest_status)

        # Check for delayed shipment
        check_delayed_shipment!

        {
          success: true,
          status: latest_status,
          tracking_events: @shipment.tracking_events.order(event_timestamp: :desc).limit(5),
          delivery_estimate: tracking_data[:estimated_delivery]
        }
      rescue StandardError => e
        log_tracking_error(e.message)
        { success: false, error: "추적 오류: #{e.message}" }
      end
    end

    # Track multiple shipments in batch
    #
    # @param shipments [Array<Shipment>] Shipments to track
    # @return [Hash] Batch tracking results
    def self.track_batch(shipments)
      results = {}

      shipments.each do |shipment|
        begin
          tracker = new(shipment)
          result = tracker.track
          results[shipment.id] = result
        rescue CarrierNotFoundError => e
          results[shipment.id] = { success: false, error: e.message }
        rescue StandardError => e
          results[shipment.id] = { success: false, error: "추적 실패: #{e.message}" }
        end

        # Sleep briefly to avoid rate limiting
        sleep 1
      end

      {
        success: true,
        results:,
        total: shipments.size,
        succeeded: results.values.count { |r| r[:success] },
        failed: results.values.count { |r| !r[:success] }
      }
    end

    # Get tracking URL for shipment
    #
    # @return [String] Tracking URL
    def tracking_url
      @carrier[:tracking_url]&.gsub('{tracking_number}', @shipment.tracking_number)
    end

    # Check if shipment is delayed
    #
    # @return [Boolean] True if delayed
    def delayed?
      return false if @shipment.delivered_at || @shipment.cancelled_at

      expected_date = @shipment.estimated_delivery_date
      return false unless expected_date

      Time.current > expected_date + 1.day
    end

    # Get estimated delivery date
    #
    # @return [Date, nil] Estimated delivery date
    def estimated_delivery_date
      @shipment.estimated_delivery_date || @shipment.current_location&.dig(:estimated_date)
    end

    private

    # Fetch tracking data from carrier API
    #
    # @return [Hash] Tracking data
    def fetch_from_api
      # Placeholder for actual API integration
      # Each carrier would have specific API integration here
      {
        current_location: { city: '서울', country: 'KR' },
        estimated_delivery: (@shipment.estimated_delivery_date || Date.today + 3.days),
        events: [
          {
            status_code: 'IN_TRANSIT',
            description: '배송 중',
            location: '서울 물류센터',
            timestamp: Time.current - 1.day
          }
        ],
        raw_data: { api: @carrier[:api_url] }
      }
    end

    # Fetch tracking data by scraping
    #
    # @return [Hash] Tracking data
    def fetch_from_scrape
      # Placeholder for scraping implementation
      # Would use tools like Nokogiri or Puppeteer for actual scraping
      {
        current_location: { city: '서울', country: 'KR' },
        estimated_delivery: (@shipment.estimated_delivery_date || Date.today + 3.days),
        events: [
          {
            status_code: 'PICKED_UP',
            description: '상품 인수',
            location: '발송 지점',
            timestamp: Time.current - 2.days
          },
          {
            status_code: 'IN_TRANSIT',
            description: '배송 중',
            location: '서울 물류센터',
            timestamp: Time.current - 1.day
          }
        ],
        raw_data: { scrape: @carrier[:scrape_url] }
      }
    end

    # Process and save tracking events
    #
    # @param tracking_data [Hash] Raw tracking data
    # @return [Symbol] Latest status
    def process_tracking_events(tracking_data)
      events = tracking_data[:events] || []
      latest_status = :unknown

      events.each do |event|
        status_code = event[:status_code]
        status = STATUS_MAP[status_code] || :unknown

        # Check if event already exists
        existing_event = @shipment.tracking_events.find_by(
          status_code:,
          event_timestamp: event[:timestamp]
        )

        next if existing_event

        # Create new tracking event
        @shipment.tracking_events.create!(
          status_code:,
          status_description: event[:description],
          location: event[:location] || '',
          event_timestamp: event[:timestamp],
          raw_data: event.except(:status_code, :description, :location, :timestamp)
        )

        latest_status = status if status != :unknown
      end

      latest_status
    end

    # Update order status based on delivery status
    #
    # @param delivery_status [Symbol] Latest delivery status
    def update_order_status!(delivery_status)
      order = @shipment.order
      return unless order

      case delivery_status
      when :delivered
        # Use OrderProcessor to mark as delivered
        processor = OrderProcessor.new(order)
        processor.process_delivery if order.status.to_sym != :delivered
      when :returned
        processor = OrderProcessor.new(order)
        processor.process_return if order.status.to_sym != :returned
      end
    rescue StandardError => e
      Rails.logger.error "Failed to update order status: #{e.message}"
    end

    # Check and flag delayed shipment
    #
    # @raise [TrackingError] if shipment is delayed
    def check_delayed_shipment!
      return unless delayed?

      # Check if delay flag already set
      return if @shipment.is_delayed

      # Mark as delayed
      @shipment.update!(is_delayed: true, delay_reason: '예상 배송일 초과')

      # Create alert
      create_delay_alert!

      raise TrackingError, "배송이 지연되었습니다. 예상 배송일: #{@shipment.estimated_delivery_date}"
    end

    # Create delay alert
    def create_delay_alert!
      order = @shipment.order
      return unless order

      # Notify relevant users (admin, seller, etc.)
      Rails.logger.warn "Shipment #{@shipment.id} is delayed for order #{order.id}"

      # TODO: Implement notification system
      # - Send email to customer service
      # - Update dashboard alert
    end

    # Log tracking error
    #
    # @param error_message [String] Error message
    def log_tracking_error(error_message)
      Rails.logger.error "Tracking error for shipment #{@shipment.id}: #{error_message}"

      AuditLog.create(
        account: @shipment.account,
        action_type: 'error',
        entity_type: 'Shipment',
        entity_id: @shipment.id,
        details: { tracking_number: @shipment.tracking_number, error_message: }
      )
    end
  end
end
