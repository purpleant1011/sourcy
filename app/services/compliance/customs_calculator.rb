# frozen_string_literal: true

# 관세 계산 서비스
# 수입 제품의 관세와 부가가치세를 계산합니다.
# @see PRD Section 5.5 for customs duty calculation rules
module Compliance
  class CustomsCalculator
    class CalculationError < StandardError; end

    # 관세율 표 (예시)
    # 실제로는 KCS(한국관세청) API 또는 관세청 홈페이지 데이터를 참조
    DUTY_RATES = {
      # 의류/패션
      '61' => 0.13,  # 편직물류
      '62' => 0.13,  # 비편직물류
      '63' => 0.13,  # 기타 제품
      
      # 전자제품
      '84' => 0.08,  # 기계류
      '85' => 0.08,  # 전자기기
      
      # 가정용품
      '73' => 0.06,  # 철강제품
      '94' => 0.08,  # 가구
      
      # 식품/음료
      '04' => 0.08,  # 유제품
      '19' => 0.08,  # 곡물 가공품
      '21' => 0.20,  # 조미식품
      
      # 화장품
      '33' => 0.08,  # 향수/화장품
      
      # 완구/완구
      '95' => 0.08,  # 완구/완구
      
      # 기본 관세율
      'default' => 0.08
    }.freeze

    # 부가가치세율
    VAT_RATE = 0.10

    # 미국관세청(FAS) 구매 면세 한도 (200달러)
    DUTY_FREE_THRESHOLD_USD = 200

    attr_reader :product, :options

    # 관세 계산 서비스 초기화
    #
    # @param product [CatalogProduct, SourceProduct] 계산할 제품
    # @param options [Hash] 추가 옵션
    # @option options [String] :original_currency 원래 통화 (default: CNY)
    # @option options [Integer] :original_price_cents 원래 가격 (cents)
    # @option options [String] :hs_code HS 코드
    # @option options [Integer] :quantity 수량 (default: 1)
    # @option options [Boolean] :include_vat 부가세 포함 여부 (default: true)
    # @option options [Float] :custom_rate 커스텀 관세율 (선택사항)
    def initialize(product:, options: {})
      @product = product
      @options = options
      @original_currency = options[:original_currency] || 'CNY'
      @original_price_cents = options[:original_price_cents]
      @hs_code = options[:hs_code]
      @quantity = options[:quantity] || 1
      @include_vat = options[:include_vat] != false
      @custom_rate = options[:custom_rate]
    end

    # 관세 계산
    #
    # @return [Hash] 관세 계산 결과
    def calculate
      # 1. 원래 가격 확인
      original_price = get_original_price

      # 2. FX 환율로 원화 변환
      fx_rate = get_fx_rate(@original_currency)
      base_price_krw = (original_price * fx_rate).to_i

      # 3. 관세율 결정
      duty_rate = get_duty_rate

      # 4. 관세 계산
      duty_amount_krw = calculate_duty(base_price_krw, duty_rate)

      # 5. 부가가치세 계산 (관세를 포함한 금액에 대해)
      vat_amount_krw = calculate_vat(base_price_krw, duty_amount_krw) if @include_vat

      # 6. 총 비용 계산
      total_duty_krw = duty_amount_krw + (vat_amount_krw || 0)

      # 7. 면세 여부 확인
      duty_free = check_duty_free(base_price_krw)

      {
        base_price_krw: base_price_krw,
        fx_rate: fx_rate,
        fx_rate_date: fx_rate_date,
        duty_rate: duty_rate,
        duty_rate_percent: (duty_rate * 100).round(2),
        duty_amount_krw: duty_amount_krw,
        vat_rate_percent: (VAT_RATE * 100).round(2),
        vat_amount_krw: vat_amount_krw || 0,
        total_duty_krw: total_duty_krw,
        duty_free: duty_free,
        quantity: @quantity,
        per_unit_duty_krw: duty_free ? 0 : (total_duty_krw / @quantity).to_i
      }
    end

    # 관세율만 조회
    #
    # @return [Float] 관세율 (0.0 ~ 1.0)
    def get_duty_rate
      return @custom_rate if @custom_rate.present?

      hs_prefix = extract_hs_prefix(@hs_code)
      DUTY_RATES[hs_prefix] || DUTY_RATES['default']
    end

    # 총 관세 포함 가격 계산 (원래 가격 + 관세 + 부가세)
    #
    # @return [Integer] 총 금액 (KRW cents)
    def calculate_total_with_duty
      result = calculate
      result[:base_price_krw] + result[:total_duty_krw]
    end

    # 미국직구 FAS 면세 여부 확인
    #
    # @return [Boolean] 면세 대상 여부
    def fas_duty_free?
      return false unless @original_currency == 'USD'

      original_price = get_original_price
      (original_price / 100.0) < DUTY_FREE_THRESHOLD_USD
    end

    private

    # 원래 가격 가져오기
    #
    # @return [Integer] 가격 (cents)
    def get_original_price
      return @original_price_cents if @original_price_cents.present?

      if @product.is_a?(SourceProduct)
        @product.original_price_cents
      elsif @product.is_a?(CatalogProduct)
        # 카탈로그 제품은 원래 가격이 없으므로 source_product 조회
        @product.source_product&.original_price_cents || 0
      else
        0
      end
    end

    # FX 환율 가져오기
    #
    # @param currency [String] 통화 코드
    # @return [Float] 환율
    def get_fx_rate(currency)
      # 환율 스냅샷에서 최신 환율 조회
      fx_snapshot = FxRateSnapshot
        .where(currency_pair: "#{currency}-KRW")
        .order(captured_at: :desc)
        .first

      if fx_snapshot
        @fx_rate_date = fx_snapshot.captured_at
        return fx_snapshot.rate
      end

      # 환율 데이터가 없으면 기본값 사용 (CNY: 190, USD: 1320)
      case currency
      when 'CNY'
        190.0
      when 'USD'
        1320.0
      when 'JPY'
        8.5
      when 'EUR'
        1420.0
      else
        raise CalculationError, "No FX rate available for #{currency}"
      end
    end

    # FX 환율 적용일
    #
    # @return [Time, nil]
    def fx_rate_date
      @fx_rate_date
    end

    # 관세액 계산
    #
    # @param base_price_krw [Integer] 기본 가격 (KRW cents)
    # @param duty_rate [Float] 관세율 (0.0 ~ 1.0)
    # @return [Integer] 관세액 (KRW cents)
    def calculate_duty(base_price_krw, duty_rate)
      return 0 if duty_rate.zero?

      # 관세 = CIF 가격 × 관세율
      # CIF = Cost(상품가격) + Insurance(보험료) + Freight(운송비)
      # 간단하게 상품가격에 대해서만 계산
      (base_price_krw * duty_rate * @quantity).to_i
    end

    # 부가가치세 계산
    #
    # @param base_price_krw [Integer] 기본 가격 (KRW cents)
    # @param duty_amount_krw [Integer] 관세액 (KRW cents)
    # @return [Integer] 부가가치세 (KRW cents)
    def calculate_vat(base_price_krw, duty_amount_krw)
      # 부가세 = (과세표준 × 10%)
      # 과세표준 = 상품가격 + 관세
      taxable_amount = base_price_krw + duty_amount_krw
      (taxable_amount * VAT_RATE).to_i
    end

    # HS 코드 앞 2자리 추출
    #
    # @param hs_code [String] HS 코드
    # @return [String] HS 코드 앞 2자리
    def extract_hs_prefix(hs_code)
      return nil unless hs_code.present?

      hs_code.to_s[0..1]
    end

    # 면세 여부 확인
    #
    # @param base_price_krw [Integer] 기본 가격 (KRW cents)
    # @return [Boolean] 면세 여부
    def check_duty_free(base_price_krw)
      # 한국 관세청: 미국직구 200달러 미만, 기타 150달러 미만 면세
      # 간단하게 계산 (USD 기준)
      base_price_usd = base_price_krw / 1320.0 # 대략적인 USD 환율

      fas_duty_free? || base_price_usd < 150
    end
  end
end
