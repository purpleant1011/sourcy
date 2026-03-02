# frozen_string_literal: true

# KC 인증 체크 서비스
# 제품 카테고리별 KC 인증 여부를 확인합니다.
# @see PRD Section 5.4 for KC certification requirements
module Compliance
  class KcCertChecker
    class CheckError < StandardError; end

    attr_reader :product, :options

    # KC 인증 체크 서비스 초기화
    #
    # @param product [CatalogProduct, SourceProduct] 확인할 제품
    # @param options [Hash] 추가 옵션
    # @option options [String] :category_code 제품 카테고리 코드
    # @option options [String] :hs_code HS 코드
    # @option options [Boolean] :strict_mode 엄격한 모드 (default: true)
    def initialize(product:, options: {})
      @product = product
      @options = options
      @strict_mode = options[:strict_mode] || true
      @category_code = options[:category_code]
      @hs_code = options[:hs_code]
    end

    # KC 인증 필요 여부 확인
    #
    # @return [Hash] 인증 체크 결과
    def check
      result = {
        required: false,
        kc_cert_status: :unknown,
        exemptions: [],
        requirements: [],
        risk_level: :low
      }

      # 1. 카테고리 기반 체크
      category_result = check_by_category
      result[:required] ||= category_result[:required]
      result[:kc_cert_status] = category_result[:status]
      result[:exemptions].concat(category_result[:exemptions])

      # 2. HS 코드 기반 체크
      if @hs_code.present?
        hs_result = check_by_hs_code
        result[:required] ||= hs_result[:required]
        result[:requirements].concat(hs_result[:requirements])
      end

      # 3. 키워드 기반 체크 (제품 설명, 속성)
      keyword_result = check_by_keywords
      result[:risk_level] = keyword_result[:risk_level]

      # 4. 브랜드 기반 체크
      brand_result = check_by_brand
      result[:risk_level] = [:risk_level, brand_result[:risk_level]].max

      # 최종 상태 결정
      determine_final_status(result)

      result
    end

    # 제품의 KC 인증 상태 업데이트
    #
    # @return [Boolean] 업데이트 성공 여부
    def update_product_status
      return false unless @product.is_a?(CatalogProduct)

      result = check

      @product.update!(
        kc_cert_status: result[:kc_cert_status],
        kc_cert_required: result[:required]
      )

      true
    rescue StandardError => e
      Rails.logger.error "Failed to update KC cert status: #{e.message}"
      false
    end

    private

    # 카테고리별 KC 인증 확인
    #
    # @return [Hash] 카테고리 체크 결과
    def check_by_category
      category = @category_code || extract_category_from_product

      # KC 인증 규칙 조회
      rule = KcCertRule.find_by(product_category: category)

      return { required: false, status: :exempted, exemptions: ["category_not_regulated"] } unless rule

      # 규칙에 따른 인증 필요 여부 확인
      if rule.exempted?
        { required: false, status: :exempted, exemptions: [rule.exemption_reason] }
      elsif rule.required?
        { required: true, status: :pending, exemptions: [] }
      else
        { required: false, status: :exempted, exemptions: ["category_optional"] }
      end
    rescue StandardError => e
      Rails.logger.error "Category check failed: #{e.message}"
      { required: false, status: :unknown, exemptions: [] }
    end

    # HS 코드 기반 KC 인증 확인
    #
    # @return [Hash] HS 코드 체크 결과
    def check_by_hs_code
      # HS 코드별 KC 인증 규칙 (예시)
      hs_rules = {
        '85' => :electronics,      # 전자기기
        '86' => :electronics,      # 철도차량 등
        '87' => :automotive,       # 자동차
        '90' => :medical,         # 의료기기
        '95' => :toys             # 완구
      }

      hs_prefix = @hs_code.to_s[0..1]
      category_type = hs_rules[hs_prefix]

      return { required: false, requirements: [] } unless category_type

      # 카테고리별 요구사항
      requirements = case category_type
      when :electronics
        [
          { type: :emc, description: '전자파적합성 시험' },
          { type: :safety, description: '안전성 시험' }
        ]
      when :automotive
        [
          { type: :ks, description: 'KS 인증' },
          { type: :kmvss, description: '자동차안전기준' }
        ]
      when :medical
        [
          { type: :kgmp, description: '의약품등허가' },
          { type: :kmds, description: '의료기기관리법' }
        ]
      when :toys
        [
          { type: :kc, description: '어린이제품 KC 인증' },
          { type: :safety, description: '안전성 확인' }
        ]
      else
        []
      end

      { required: true, requirements: requirements }
    end

    # 키워드 기반 체크 (제품 설명, 속성)
    #
    # @return [Hash] 키워드 체크 결과
    def check_by_keywords
      return { risk_level: :low } unless @product.is_a?(CatalogProduct)

      text = [
        @product.translated_title,
        @product.translated_description,
        @product.attributes.values.join(' ')
      ].join(' ').downcase

      # 높은 리스크 키워드
      high_risk_keywords = %w[
        전기 가전 전자 배터리 충전기
        의료 의약품 약 건강기능
        어린이 유아 아동 완구 장난감
        자동차 부품 타이어
      ]

      # 중간 리스크 키워드
      medium_risk_keywords = %w[
        식품 음료 화장품
        안전 인증 kc 마크
      ]

      risk_count = high_risk_keywords.count { |kw| text.include?(kw) }
      risk_count += medium_risk_keywords.count { |kw| text.include?(kw) } * 0.5

      if risk_count >= 2
        { risk_level: :high }
      elsif risk_count >= 1
        { risk_level: :medium }
      else
        { risk_level: :low }
      end
    end

    # 브랜드 기반 체크
    #
    # @return [Hash] 브랜드 체크 결과
    def check_by_brand
      return { risk_level: :low } unless @product.is_a?(CatalogProduct)

      brand = @product.attributes.dig('brand')

      return { risk_level: :low } if brand.blank?

      # 브랜드 필터 확인
      filter = BrandFilter.find_by(brand_name: brand.downcase)

      return { risk_level: :low } unless filter

      if filter.block?
        { risk_level: :high }
      elsif filter.warn?
        { risk_level: :medium }
      else
        { risk_level: :low }
      end
    end

    # 최종 KC 인증 상태 결정
    #
    # @param result [Hash] 체크 결과
    def determine_final_status(result)
      if result[:required]
        result[:kc_cert_status] = :pending
      elsif !result[:exemptions].empty?
        result[:kc_cert_status] = :exempted
      else
        result[:kc_cert_status] = :unknown
      end
    end

    # 제품에서 카테고리 추출
    #
    # @return [String] 카테고리 코드
    def extract_category_from_product
      return nil unless @product.is_a?(CatalogProduct)

      @product.attributes.dig('category') || 'general'
    end
  end
end
