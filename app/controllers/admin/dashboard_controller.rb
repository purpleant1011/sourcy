# frozen_string_literal: true

module Admin
  class DashboardController < Admin::BaseController
    def index
      @total_products = CatalogProduct.where(account: Current.account).count
      @active_listings = MarketplaceListing.joins(:marketplace_account)
        .where(marketplace_accounts: { account_id: Current.account&.id }).count
      @today_orders = Order.where(account: Current.account)
        .where(created_at: Date.current.all_day).count
      @pending_tasks = ExtractionRun
        .where(status: :pending)
        .joins(:source_product)
        .where(source_products: { account_id: Current.account&.id })
        .count
      @recent_orders = Order.where(account: Current.account).order(created_at: :desc).limit(5)
    end
  end
end
