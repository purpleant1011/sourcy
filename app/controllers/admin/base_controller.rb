# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include Pagy::Backend
    layout "admin"
    skip_before_action :authenticate
    skip_before_action :set_current_account
    before_action :require_basic_auth

    private

    def require_basic_auth
      authenticate_or_request_with_http_basic do |username, password|
        expected_user = Rails.application.credentials.dig(:admin, :username).to_s
        expected_pass = Rails.application.credentials.dig(:admin, :password).to_s

        expected_user = ENV.fetch("ADMIN_USERNAME", "admin") if expected_user.blank?
        expected_pass = ENV.fetch("ADMIN_PASSWORD", "password") if expected_pass.blank?

        authenticated = ActiveSupport::SecurityUtils.secure_compare(username, expected_user) &&
                        ActiveSupport::SecurityUtils.secure_compare(password, expected_pass)

        Current.account = Account.first if authenticated
        authenticated
      end
    end
  end
end
