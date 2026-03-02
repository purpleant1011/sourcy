# frozen_string_literal: true

# 브랜드 필터 서비스
# 제품의 브랜드가 위험 브랜드(가품, 저작권 문제)인지 확인합니다.
# @see PRD Section 5.6 for brand filtering rules
module Compliance
  class BrandFilterService
    class FilterError < StandardError; end

    attr_reader :product, :options

    # 브랜드 필터 서비스 초기화
    #
    # @param product [CatalogProduct, SourceProduct] 확인할 제품
    # @param options [Hash] 추가 옵션
    # @option options [String] :brand_name 브랜드 이름
    # @option options [Boolean] :auto_create 필터 자동 생성 여부 (default: false)
    # @option options [Boolean] :strict_mode 엄격한 모드 (default: true)
    def initialize(product:, options: {})
      @product = product
      @options = options
      @strict_mode = options[:strict_mode] != false
      @auto_create = options[:auto_create] || false
      @brand_name = options[:brand_name]
    end

    # 브랜드 필터링 확인
    #
    # @return [Hash] 필터링 결과
    def check
      result = {
        blocked: false,
        warned: false,
        filter: nil,
        risk_level: :low,
        matched_keywords: [],
        suggestions: []
      }

      # 1. 브랜드 이름 추출
      brand = extract_brand_name
      return result if brand.blank?

      # 2. 브랜드 필터 확인
      filter = BrandFilter.find_by("LOWER(brand_name) = ?", brand.downcase)

      if filter
        result[:filter] = filter
        result[:blocked] = filter.block?
        result[:warned] = filter.warn?
        result[:risk_level] = filter.block? ? :high : :medium
      else
        # 3. 키워드 기반 위험 브랜드 패턴 확인
        pattern_result = check_brand_patterns(brand)
        result.update(pattern_result)
      end

      # 4. 제품 설명/속성에서 위험 키워드 확인
      keyword_result = check_risky_keywords
      result[:matched_keywords].concat(keyword_result[:matched_keywords])

      if result[:matched_keywords].any?
        result[:risk_level] = [:risk_level, :medium].max
        result[:warned] = true
      end

      # 5. 제안 사항 생성
      generate_suggestions(result, brand)

      result
    end

    # 브랜드 필터 업데이트 (차단/경고)
    #
    # @param action [Symbol] :block 또는 :warn
    # @return [Boolean] 업데이트 성공 여부
    def update_filter(action)
      return false unless [:block, :warn].include?(action)

      brand = extract_brand_name
      return false if brand.blank?

      filter = BrandFilter.find_or_initialize_by(
        brand_name: brand.downcase
      )

      filter.action = action
      filter.save!

      true
    rescue StandardError => e
      Rails.logger.error "Failed to update brand filter: #{e.message}"
      false
    end

    # 제품의 브랜드 안전 여부 확인
    #
    # @return [Boolean] 안전한 브랜드인지 여부
    def safe?
      result = check
      !result[:blocked] && result[:risk_level] == :low
    end

    # 위험 브랜드인지 확인
    #
    # @return [Boolean] 위험 브랜드인지 여부
    def dangerous?
      result = check
      result[:blocked] || result[:warned]
    end

    private

    # 브랜드 이름 추출
    #
    # @return [String, nil] 브랜드 이름
    def extract_brand_name
      return @brand_name if @brand_name.present?

      if @product.is_a?(CatalogProduct)
        @product.attributes.dig('brand')
      elsif @product.is_a?(SourceProduct)
        @product.original_attributes.dig('brand')
      else
        nil
      end
    end

    # 브랜드 패턴 확인 (위험 브랜드 유형)
    #
    # @param brand [String] 브랜드 이름
    # @return [Hash] 패턴 체크 결과
    def check_brand_patterns(brand)
      result = {
        blocked: false,
        warned: false,
        risk_level: :low,
        matched_patterns: []
      }

      brand_lower = brand.downcase

      # 1. 유명 브랜드 확인 (예시)
      luxury_brands = %w[
        chanel louis-vuitton gucci dior hermes prada
        balenciaga fendi burberry versace armani
        rolex omega cartier tiffany chopard
      ]

      if luxury_brands.any? { |b| brand_lower.include?(b) }
        result[:warned] = true
        result[:risk_level] = :medium
        result[:matched_patterns] << 'luxury_brand'
      end

      # 2. 스포츠 브랜드 확인
      sports_brands = %w[
        nike adidas puma reebok new-balance under-armour
      ]

      if sports_brands.any? { |b| brand_lower.include?(b) }
        result[:warned] = true
        result[:risk_level] = :medium
        result[:matched_patterns] << 'sports_brand'
      end

      # 3. 전자제품 브랜드 확인
      tech_brands = %w[
        apple samsung lg sony microsoft dell
        hp lenovo toshiba asus acer
      ]

      if tech_brands.any? { |b| brand_lower.include?(b) }
        result[:warned] = true
        result[:risk_level] = :medium
        result[:matched_patterns] << 'tech_brand'
      end

      # 4. 의심스러운 패턴 확인 (가품 표시)
      if brand_lower.match?(/(fake|copy|replica|oem|knockoff|imitation)/)
        result[:blocked] = true
        result[:risk_level] = :high
        result[:matched_patterns] << 'fake_indication'
      end

      result
    end

    # 위험 키워드 확인
    #
    # @return [Hash] 키워드 체크 결과
    def check_risky_keywords
      result = {
        matched_keywords: []
      }

      return result unless @product.is_a?(CatalogProduct)

      text = [
        @product.translated_title,
        @product.translated_description,
        @product.attributes.values.join(' ')
      ].join(' ').downcase

      # 위험 키워드 목록
      risky_keywords = {
        '가품' => :high,
        '모조품' => :high,
        '복제품' => :high,
        '짝퉁' => :high,
        '1:1' => :medium,
        'copy' => :medium,
        'replica' => :medium,
        'oem' => :low,
        'factory' => :low,
        'direct' => :low
      }

      risky_keywords.each do |keyword, risk|
        if text.include?(keyword)
          result[:matched_keywords] << {
            keyword: keyword,
            risk: risk
          }
        end
      end

      result
    end

    # 제안 사항 생성
    #
    # @param result [Hash] 필터링 결과
    # @param brand [String] 브랜드 이름
    def generate_suggestions(result, brand)
      if result[:blocked]
        result[:suggestions] << {
          type: :error,
          message: "이 브랜드는 차단되었습니다. 다른 브랜드를 사용하세요."
        }
      elsif result[:warned]
        result[:suggestions] << {
          type: :warning,
          message: "이 브랜드는 주의가 필요합니다. 저작권 문제가 있을 수 있습니다."
        }

        if result[:matched_patterns].include?('luxury_brand')
          result[:suggestions] << {
            type: :info,
            message: "럭셔리 브랜드는 주의가 필요합니다. 공식 수입 여부를 확인하세요."
          }
        end

        if result[:matched_keywords].any? { |k| k[:risk] == :high }
          result[:suggestions] << {
            type: :error,
            message: "가품/모조품 관련 키워드가 감지되었습니다. 제품 설명을 수정하세요."
          }
        end
      elsif result[:matched_patterns].any? || result[:matched_keywords].any?
        result[:suggestions] << {
          type: :info,
          message: "브랜드 확인이 필요합니다."
        }
      end
    end
  end
end
