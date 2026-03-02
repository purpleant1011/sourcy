# frozen_string_literal: true

# Account settings controller for managing account details
module Admin
  module Settings
    class AccountsController < ApplicationController
      before_action :set_account

      # Show account settings
      def show
        @subscription = @account.subscription
        @api_credentials = @account.api_credentials
        @usage_stats = calculate_usage_stats
      end

      # Update account settings
      def update
        if @account.update(account_params)
          respond_to do |format|
            format.turbo_stream { render :update }
            format.html { redirect_to admin_accounts_path, notice: '계정 설정이 저장되었습니다.' }
          end
        else
          respond_to do |format|
            format.turbo_stream { render :update, status: :unprocessable_entity }
            format.html { render :show, status: :unprocessable_entity }
          end
        end
      end

      private

      def set_account
        @account = Current.account
      end

      def account_params
        params.require(:account).permit(
          :name,
          :company_name,
          :business_number,
          :contact_phone,
          :contact_email,
          :address,
          :business_type,
          :vat_number,
          settings: {}
        )
      end

      def calculate_usage_stats
        {
          source_products_count: @account.source_products.count,
          catalog_products_count: @account.catalog_products.count,
          marketplace_listings_count: @account.marketplace_listings.count,
          orders_count: @account.orders.count,
          storage_used: calculate_storage_usage,
          monthly_api_calls: calculate_monthly_api_calls
        }
      end

      def calculate_storage_usage
        # Calculate storage usage in MB
        # This would be calculated from ActiveStorage attachments
        0 # Placeholder
      end

      def calculate_monthly_api_calls
        # Calculate API calls this month
        # This would be calculated from logs or metrics
        @account.api_credentials.sum { |cred| cred.api_calls || 0 }
      end
    end
  end
end
