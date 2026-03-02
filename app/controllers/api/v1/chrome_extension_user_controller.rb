# frozen_string_literal: true

module Api
  module V1
    class ChromeExtensionUserController < BaseController
      # Get current user info
      # Chrome Extension popup에서 호출
      def show
        user = Current.user
        account = Current.account

        return render_error(
          code: "AUTH_REQUIRED",
          message: "Authentication required",
          status: :unauthorized
        ) if user.blank? || account.blank?

        user_data = {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role.to_s,
          account_id: account.id,
          account_name: account.name,
          business_type: account.business_type.to_s,
          status: account.status.to_s,
          created_at: account.created_at&.iso8601
        }

        # Add subscription info if available
        if account.current_subscription.present?
          user_data[:subscription] = {
            plan: account.current_subscription.plan_name,
            status: account.current_subscription.status.to_s,
            expires_at: account.current_subscription.expires_at&.iso8601
          }
        end

        # Add usage stats
        user_data[:usage] = {
          products_count: SourceProduct.where(account_id: account.id).count,
          listed_count: CatalogProduct.where(account_id: account.id).where(status: :listed).count,
          this_month_imports: SourceProduct
            .where(account_id: account.id)
            .where('collected_at >= ?', Time.current.beginning_of_month)
            .count
        }

        # Add API key for extension (encrypted)
        user_data[:api_key] = generate_api_key_for_extension(user)

        render_success(data: user_data)
      end

      # Update user profile
      def update
        user = Current.user

        user.update!(user_params)

        render_success(data: {
          id: user.id,
          email: user.email,
          name: user.name
        })
      end

      # Change account settings
      def update_account
        account = Current.account

        account.update!(account_params)

        render_success(data: {
          id: account.id,
          name: account.name,
          business_type: account.business_type.to_s
        })
      end

      private

      # Strong parameters for user update
      def user_params
        params.permit(:name, :password, :password_confirmation)
      end

      # Strong parameters for account update
      def account_params
        params.permit(:name, :business_type)
      end

      # Generate API key for Chrome Extension
      def generate_api_key_for_extension(user)
        # Generate a unique API key for the extension
        # This key is used to identify the extension for analytics and rate limiting
        raw_key = "sk_ext_#{user.account_id}_#{user.id}_#{SecureRandom.hex(16)}"

        # Hash for storage (don't store raw key)
        hashed_key = Digest::SHA256.hexdigest(raw_key)

        # Return a shortened version for display
        raw_key[0..3] + "..." + raw_key[-4..-1]
      end
    end
  end
end
