# frozen_string_literal: true

# Settlement calculation service
# Calculates fees and settlements for marketplace orders
module OrderProcessing
  class SettlementCalculator
    class CalculationError < StandardError; end

    # Marketplace fee configuration
    MARKETPLACE_FEES = {
      smart_store: {
        base_rate: 0.011,      # 1.1% 기본 수수료
        payment_fee: 0.055,    # 5.5% 결제 수수료
        category_rates: {
          'fashion' => 0.011,
          'electronics' => 0.013,
          'home' => 0.011,
          'beauty' => 0.011,
          'food' => 0.007,
          'other' => 0.011
        },
        min_fee: 0,                # 최소 수수료 (KRW)
        vat_rate: 0.10             # 부가세율 10%
      },
      coupang: {
        base_rate: 0.105,      # 10.5% 기본 수수료 (베스트 마켓)
        payment_fee: 0.055,    # 5.5% 결제 수수료
        category_rates: {},
        best_mall_rate: 0.021, # 베스트 마켓 추가 수수료 2.1%
        min_fee: 0,
        vat_rate: 0.10
      },
      gmarket: {
        base_rate: 0.11,       # 11% 기본 수수료
        payment_fee: 0.055,    # 5.5% 결제 수수료
        category_rates: {
          'fashion' => 0.11,
          'electronics' => 0.115,
          'home' => 0.11,
          'beauty' => 0.11,
          'other' => 0.11
        },
        min_fee: 0,
        vat_rate: 0.10
      },
      elevenst: {
        base_rate: 0.115,      # 11.5% 기본 수수료
        payment_fee: 0.055,    # 5.5% 결제 수수료
        category_rates: {},
        min_fee: 0,
        vat_rate: 0.10
      }
    }.freeze

    # Initialize settlement calculator
    #
    # @param order [Order] The order to calculate
    # @param account [Account] The account context
    def initialize(order, account = nil)
      @order = order
      @account = account || order.account
      @marketplace = order.marketplace.to_sym
      @fee_config = MARKETPLACE_FEES[@marketplace]
    end

    # Calculate complete settlement breakdown
    #
    # @param options [Hash] Calculation options
    # @return [Hash] Settlement breakdown
    def calculate(options = {})
      unless @fee_config
        return { success: false, error: "지원하지 않는 마켓플레이스: #{@marketplace}" }
      end

      # Calculate total sales amount
      sales_amount = @order.total_amount_krw
      shipping_fee = @order.shipping_fee_krw || 0

      # Calculate marketplace fees
      base_fee = calculate_base_fee(sales_amount, shipping_fee)
      payment_fee = calculate_payment_fee(sales_amount)
      category_fee = calculate_category_fee(sales_amount)

      # Total marketplace fee
      total_marketplace_fee = base_fee + payment_fee + category_fee

      # Calculate VAT
      vat_amount = calculate_vat(sales_amount - total_marketplace_fee)

      # Net amount (payout)
      net_amount = sales_amount - total_marketplace_fee - vat_amount

      # Calculate withholding tax (if applicable)
      withholding_tax = calculate_withholding_tax(net_amount) if options[:apply_withholding]

      # Final payout
      final_payout = withholding_tax ? net_amount - withholding_tax : net_amount

      {
        success: true,
        marketplace: @marketplace,
        sales_amount:,
        shipping_fee:,
        base_fee:,
        payment_fee:,
        category_fee:,
        total_marketplace_fee:,
        vat_amount:,
        withholding_tax: withholding_tax || 0,
        final_payout:,
        breakdown: {
          base_rate: @fee_config[:base_rate],
          payment_rate: @fee_config[:payment_fee],
          vat_rate: @fee_config[:vat_rate],
          applied_category_rate: get_applied_category_rate
        }
      }
    rescue StandardError => e
      Rails.logger.error "Settlement calculation failed: #{e.message}"
      { success: false, error: "정산 계산 오류: #{e.message}" }
    end

    # Create settlement record
    #
    # @param options [Hash] Settlement options
    # @return [Settlement] Created settlement record
    def create_settlement(options = {})
      calculation = calculate(options)

      return nil unless calculation[:success]

      ApplicationRecord.transaction do
        Settlement.create!(
          account: @account,
          marketplace: @marketplace.to_s,
          order: @order,
          settlement_type: options[:type] || :delivery,
          amount_krw: calculation[:final_payout],
          sales_amount_krw: calculation[:sales_amount],
          shipping_fee_krw: calculation[:shipping_fee],
          marketplace_fee_krw: calculation[:total_marketplace_fee],
          vat_amount_krw: calculation[:vat_amount],
          withholding_tax_krw: calculation[:withholding_tax] || 0,
          settlement_date: Time.current,
          status: :pending,
          details: calculation[:breakdown]
        )
      end
    end

    # Generate settlement report for period
    #
    # @param start_date [Date] Report start date
    # @param end_date [Date] Report end date
    # @param marketplace [Symbol, nil] Filter by marketplace (optional)
    # @return [Hash] Settlement report data
    def self.generate_report(start_date, end_date, marketplace = nil)
      # Query settlements for the period
      settlements = Settlement.where(
        settlement_date: start_date.beginning_of_day..end_date.end_of_day
      )

      settlements = settlements.where(marketplace: marketplace.to_s) if marketplace

      # Calculate totals
      total_sales = settlements.sum(:sales_amount_krw)
      total_fees = settlements.sum(:marketplace_fee_krw)
      total_vat = settlements.sum(:vat_amount_krw)
      total_withholding = settlements.sum(:withholding_tax_krw)
      total_payouts = settlements.sum(:amount_krw)

      # Group by marketplace
      by_marketplace = settlements.group(:marketplace).sum(:amount_krw)

      # Group by status
      by_status = settlements.group(:status).count

      # Order count
      order_count = settlements.distinct.count(:order_id)

      {
        success: true,
        period: { start_date:, end_date: },
        summary: {
          total_sales:,
          total_fees:,
          total_vat:,
          total_withholding:,
          total_payouts:,
          net_payout_rate: total_sales > 0 ? (total_payouts.to_f / total_sales * 100).round(2) : 0
        },
        by_marketplace:,
        by_status:,
        order_count:,
        settlements: settlements.order(settlement_date: :desc).limit(100)
      }
    end

    # Validate settlement amount
    #
    # @param order [Order] The order
    # @param expected_payout [Integer] Expected payout amount
    # @return [Hash] Validation result
    def self.validate_payout(order, expected_payout)
      calculator = new(order)
      calculation = calculator.calculate

      return { valid: false, error: '정산 계산 실패' } unless calculation[:success]

      expected = calculation[:final_payout]
      actual = expected_payout

      difference = (actual - expected).abs
      tolerance = (expected * 0.01).to_i # 1% tolerance

      is_valid = difference <= tolerance

      {
        valid: is_valid,
        expected:,
        actual:,
        difference:,
        tolerance:,
        within_tolerance: is_valid
      }
    end

    private

    # Calculate base marketplace fee
    #
    # @param sales_amount [Integer] Sales amount
    # @param shipping_fee [Integer] Shipping fee
    # @return [Integer] Base fee amount
    def calculate_base_fee(sales_amount, shipping_fee)
      base_fee = (sales_amount * @fee_config[:base_rate]).to_i

      # Apply minimum fee
      [base_fee, @fee_config[:min_fee]].max
    end

    # Calculate payment processing fee
    #
    # @param sales_amount [Integer] Sales amount
    # @return [Integer] Payment fee
    def calculate_payment_fee(sales_amount)
      (sales_amount * @fee_config[:payment_fee]).to_i
    end

    # Calculate category-specific fee
    #
    # @param sales_amount [Integer] Sales amount
    # @return [Integer] Category fee
    def calculate_category_fee(sales_amount)
      return 0 if @fee_config[:category_rates].empty?

      category = determine_category
      rate = @fee_config[:category_rates][category] || @fee_config[:category_rates][:other] || 0

      (sales_amount * rate).to_i
    end

    # Determine product category
    #
    # @return [String] Category key
    def determine_category
      return 'other' unless @order.order_items.any?

      # Try to determine category from catalog product
      first_item = @order.order_items.first
      catalog_product = first_item&.marketplace_listing&.catalog_product

      return 'other' unless catalog_product&.category

      # Map category to fee category
      category = catalog_product.category.to_s.downcase

      case category
      when /fashion/, /clothing/, /shoe/, /accessory/
        'fashion'
      when /electronic/, /phone/, /computer/, /appliance/
        'electronics'
      when /home/, /furniture/, /living/
        'home'
      when /beauty/, /cosmetic/, /skin/
        'beauty'
      when /food/, /snack/, /beverage/
        'food'
      else
        'other'
      end
    end

    # Get applied category rate
    #
    # @return [Float, nil] Applied category rate
    def get_applied_category_rate
      category = determine_category
      @fee_config[:category_rates][category] || @fee_config[:category_rates][:other]
    end

    # Calculate VAT
    #
    # @param taxable_amount [Integer] Taxable amount
    # @return [Integer] VAT amount
    def calculate_vat(taxable_amount)
      (taxable_amount * @fee_config[:vat_rate]).to_i
    end

    # Calculate withholding tax (for sellers)
    #
    # @param net_amount [Integer] Net amount before tax
    # @return [Integer] Withholding tax amount
    def calculate_withholding_tax(net_amount)
      # Assuming 3.3% withholding tax for small businesses
      withholding_rate = 0.033

      (net_amount * withholding_rate).to_i
    end
  end
end
