# frozen_string_literal: true

module Admin
  class SettingsController < Admin::BaseController
    before_action :set_account
    before_action :set_api_credential, only: [ :update_credential ]

    def show
      if @account
        @memberships = @account.memberships.includes(:user)
        @api_credentials = @account.api_credentials
        @marketplace_accounts = @account.marketplace_accounts
      else
        @memberships = []
        @api_credentials = []
        @marketplace_accounts = []
      end
    end
    def update
      return redirect_to admin_settings_path, alert: "계정 설정을 저장할 수 없습니다." unless @account
      if @account.update(account_params)
        redirect_to admin_settings_path, notice: "계정 설정이 저장되었습니다."
      else
        render :show, status: :unprocessable_entity
      end
    end

    def create_credential
      return redirect_to admin_settings_path, alert: "계정을 찾을 수 없습니다." unless @account
      @credential = @account.api_credentials.build(api_credential_params)

      if @credential.save
        redirect_to admin_settings_path, notice: "API 자격 증명이 추가되었습니다."
      else
        @memberships = @account&.memberships&.includes(:user)
        @api_credentials = @account&.api_credentials
        render :show, status: :unprocessable_entity
      end
    end

    def update_credential
      return redirect_to admin_settings_path, alert: "계정을 찾을 수 없습니다." unless @account
      return redirect_to admin_settings_path, alert: "API 자격 증명을 찾을 수 없습니다." unless @api_credential

      if @api_credential.update(api_credential_params)
        redirect_to admin_settings_path, notice: "API 자격 증명이 업데이트되었습니다."
      else
        @memberships = @account&.memberships&.includes(:user)
        @api_credentials = @account&.api_credentials
        render :show, status: :unprocessable_entity
      end
    end

    def destroy_credential
      return redirect_to admin_settings_path, alert: "계정을 찾을 수 없습니다." unless @account
      @api_credential = @account.api_credentials.find(params[:id])
      @api_credential.destroy

      redirect_to admin_settings_path, notice: "API 자격 증명이 삭제되었습니다."
    end

    private

    def set_account
      @account = Current.account
    end

    def set_api_credential
      @api_credential = @account.api_credentials.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_settings_path, alert: "API 자격 증명을 찾을 수 없습니다."
    end

    def account_params
      params.require(:account).permit(:name, :company_name, :business_number, :contact_phone, :contact_email)
    end

    def api_credential_params
      params.require(:api_credential).permit(:provider, :access_key, :secret_key, :additional_config, :is_active)
    end
  end
end
