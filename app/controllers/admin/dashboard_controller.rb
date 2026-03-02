# frozen_string_literal: true

module Admin
  class DashboardController < Admin::BaseController
    def index
      # 기본 대시보드 페이지 렌더링 (layout: admin)
    end

    # 대시보드 통계 (Turbo Frame용)
    def stats
      total_products = CatalogProduct.where(account: Current.account).count
      active_listings = MarketplaceListing
        .joins(:marketplace_account)
        .where(marketplace_accounts: { account: Current.account })
        .where(status: :live)
        .count
      today_orders = Order
        .where(account: Current.account)
        .where("created_at >= ?", Date.current.beginning_of_day)
        .count
      pending_tasks = ExtractionRun
        .where(status: :pending)
        .joins(:source_product)
        .where(source_products: { account: Current.account })
        .count

      render turbo_stream: turbo_stream.update("dashboard_stats") do
        render partial: "stats", locals: {
          total_products:,
          active_listings:,
          today_orders:,
          pending_tasks:
        }
      end
    end

    # 최근 활동 (Turbo Frame용)
    def activities
      # AuditLog에서 최근 활동 조회
      activities = AuditLog
        .where(account: Current.account)
        .order(created_at: :desc)
        .limit(10)

      render turbo_stream: turbo_stream.update("recent_activities") do
        render partial: "activities", locals: { activities: activities }
      end
    end
  end
end
