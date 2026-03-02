# frozen_string_literal: true

# Subscription management controller for managing account subscriptions
module Admin
  module Settings
    class SubscriptionsController < ApplicationController
      before_action :set_account
      before_action :set_subscription, only: [:show, :update]

      # Show subscription details
      def show
        @subscription ||= @account.build_subscription
        @usage_stats = calculate_usage_stats
        @available_plans = available_plans
        @billing_history = billing_history
      end

      # Update subscription
      def update
        if @subscription.update(subscription_params)
          handle_subscription_change

          respond_to do |format|
            format.turbo_stream { render :update }
            format.html { redirect_to admin_subscription_path, notice: '구독이 업데이트되었습니다.' }
          end
        else
          respond_to do |format|
            format.turbo_stream { render :update, status: :unprocessable_entity }
            format.html { render :show, status: :unprocessable_entity }
          end
        end
      end

      # Cancel subscription
      def cancel
        @subscription = @account.subscription
        @subscription.update(status: :cancelled, cancel_at: params[:cancel_at] || Time.current)

        respond_to do |format|
          format.turbo_stream { render :cancel }
          format.html { redirect_to admin_subscription_path, notice: '구독이 취소되었습니다.' }
        end
      end

      # Resume cancelled subscription
      def resume
        @subscription = @account.subscription
        @subscription.update(status: :active, cancel_at: nil)

        respond_to do |format|
          format.turbo_stream { render :resume }
          format.html { redirect_to admin_subscription_path, notice: '구독이 재개되었습니다.' }
        end
      end

      # Upgrade/downgrade plan
      def change_plan
        @subscription = @account.subscription
        new_plan = params[:plan]

        if valid_plan?(new_plan)
          @subscription.update(plan: new_plan)
          handle_plan_change(new_plan)

          respond_to do |format|
            format.turbo_stream { render :change_plan }
            format.html { redirect_to admin_subscription_path, notice: '플랜이 변경되었습니다.' }
          end
        else
          respond_to do |format|
            format.turbo_stream { render :error, locals: { message: '유효하지 않은 플랜입니다.' } }
            format.html { redirect_to admin_subscription_path, alert: '유효하지 않은 플랜입니다.' }
          end
        end
      end

      private

      def set_account
        @account = Current.account
      end

      def set_subscription
        @subscription = @account.subscription || @account.build_subscription
      end

      def subscription_params
        params.require(:subscription).permit(
          :plan,
          :billing_cycle,
          :card_token,
          :card_last4,
          :card_brand
        )
      end

      def handle_subscription_change
        # Send webhook notification for subscription change
        # This would integrate with payment provider
        Rails.logger.info "Subscription changed for account #{@account.id}: #{@subscription.plan}"
      end

      def handle_plan_change(new_plan)
        # Apply proration or credit based on plan change
        # This would calculate any credit or additional charge
        Rails.logger.info "Plan changed from #{@subscription.plan_was} to #{new_plan} for account #{@account.id}"
      end

      def calculate_usage_stats
        current_period_start = @subscription.current_period_start || Time.current.beginning_of_month

        {
          source_products: @account.source_products.where('created_at >= ?', current_period_start).count,
          catalog_products: @account.catalog_products.where('created_at >= ?', current_period_start).count,
          marketplace_listings: @account.marketplace_listings.where('created_at >= ?', current_period_start).count,
          orders: @account.orders.where('created_at >= ?', current_period_start).count,
          api_calls: calculate_api_calls(current_period_start),
          storage_mb: calculate_storage_usage
        }
      end

      def calculate_api_calls(since)
        # Calculate API calls since period start
        # This would be tracked via logs or metrics
        @account.api_credentials.sum { |cred| cred.api_calls || 0 }
      end

      def calculate_storage_usage
        # Calculate storage usage in MB
        # This would be calculated from ActiveStorage attachments
        0 # Placeholder
      end

      def available_plans
        [
          { id: 'free', name: 'Free', price: 0, features: ['100 제품/월', '1 마켓플레이스', '기본 지원'] },
          { id: 'starter', name: 'Starter', price: 49_000, features: ['1,000 제품/월', '3 마켓플레이스', '이메일 지원'] },
          { id: 'professional', name: 'Professional', price: 149_000, features: ['10,000 제품/월', '무제한 마켓플레이스', '우선 지원', 'API 액세스'] },
          { id: 'enterprise', name: 'Enterprise', price: nil, features: ['무제한 제품', '무제한 마켓플레이스', '전담 매니저', '맞춤 솔루션'] }
        ]
      end

      def billing_history
        # Retrieve billing history from payment provider
        # This would integrate with PortOne or similar
        []
      end

      def valid_plan?(plan)
        available_plans.map { |p| p[:id] }.include?(plan)
      end
    end
  end
end
