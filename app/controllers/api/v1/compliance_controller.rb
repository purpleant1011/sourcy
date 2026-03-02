module Api
  module V1
    class ComplianceController < BaseController
      def kc_check
        category = params.require(:product_category)
        rule = KcCertRule.find_by(product_category: category)

        render_success(
          data: {
            product_category: category,
            cert_required: rule&.cert_required || false,
            cert_type: rule&.cert_type,
            reference_law: rule&.reference_law,
            exemption_conditions: rule&.exemption_conditions || {}
          }
        )
      end

      def brand_check
        keyword = params.require(:keyword)
        category = params[:category]
        filters = BrandFilter.where("LOWER(keyword) = ?", keyword.downcase)
        filters = filters.where(category: [ category, nil ]) if category.present?

        render_success(
          data: {
            keyword: keyword,
            flagged: filters.exists?,
            risks: filters.map { |filter| { brand_name: filter.brand_name, action: filter.action, category: filter.category } }
          }
        )
      end

      def customs_estimate
        declared_value_krw = params.require(:declared_value_krw).to_i
        duty_rate = BigDecimal(params.fetch(:duty_rate, "0").to_s)
        vat_rate = BigDecimal(params.fetch(:vat_rate, "0.1").to_s)

        duty_krw = (declared_value_krw * duty_rate).round
        vat_base = declared_value_krw + duty_krw
        vat_krw = (vat_base * vat_rate).round

        render_success(
          data: {
            declared_value_krw: declared_value_krw,
            duty_rate: duty_rate.to_f,
            vat_rate: vat_rate.to_f,
            duty_krw: duty_krw,
            vat_krw: vat_krw,
            total_estimated_tax_krw: duty_krw + vat_krw
          }
        )
      end
    end
  end
end
