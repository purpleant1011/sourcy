# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :authenticate, only: [:chrome_extension]

  # Chrome Extension OAuth2 Authorization Page
  # 사용자가 로그인하고 Chrome Extension에 권한 부여
  def chrome_extension
    auth_session_id = params[:session_id]
    @auth_session = Rails.cache.read("oauth_auth:#{auth_session_id}")

    if @auth_session.blank?
      # 세션이 만료되었거나 유효하지 않음
      @error = "Authorization session has expired. Please try again from the Chrome Extension."
      render :chrome_extension_error, status: :bad_request
      return
    end

    # 사용자가 이미 로그인되어 있으면 권한 부여 페이지 표시
    if current_user.present?
      render :chrome_extension_authorize
    else
      # 로그인하지 않았으면 로그인 페이지로 리다이렉트
      # 로그인 후 다시 이 페이지로 돌아옴
      session[:oauth_redirect] = chrome_extension_auth_path(session_id: auth_session_id)
      redirect_to new_session_path
    end
  end

  # 사용자가 권한 부여 승인
  def chrome_extension_approve
    auth_session_id = params[:session_id]
    auth_session = Rails.cache.read("oauth_auth:#{auth_session_id}")

    if auth_session.blank?
      redirect_to chrome_extension_auth_path(session_id: auth_session_id), alert: "Authorization session has expired"
      return
    end

    if current_user.blank?
      redirect_to chrome_extension_auth_path(session_id: auth_session_id), alert: "You must be logged in to authorize"
      return
    end

    # Generate authorization code
    code = generate_authorization_code(auth_session, current_user)

    # Store authorization code
    Rails.cache.write("oauth_code:#{code}", auth_session.merge({
      user_id: current_user.id,
      expires_at: 5.minutes.from_now
    }), expires_in: 5.minutes)

    # Redirect to Chrome Extension callback URL
    # Chrome Extension은 이 URL을 가로채서 code를 처리함
    redirect_to chrome_extension_callback_url(code, auth_session[:state])
  end

  # 사용자가 권한 부여 거부
  def chrome_extension_deny
    auth_session_id = params[:session_id]

    # 세션 정리
    Rails.cache.delete("oauth_auth:#{auth_session_id}")

    # 거부 응답 전달
    redirect_to chrome_extension_callback_url_with_error("access_denied", params[:state])
  end

  private

  # Generate authorization code
  def generate_authorization_code(auth_session, user)
    # PKCE code challenge 검증을 위해 세션 정보 포함
    code_data = {
      session_id: auth_session[:session_id],
      code_challenge: auth_session[:code_challenge],
      code_challenge_method: auth_session[:code_challenge_method],
      user_id: user.id,
      timestamp: Time.current.to_i
    }

    # 인코딩된 authorization code 생성
    Base64.urlsafe_encode64(code_data.to_json)[0...64]
  end

  # Chrome Extension callback URL
  def chrome_extension_callback_url(code, state)
    # Chrome Extension이 등록한 redirect URI
    # Manifest V3에서는 chrome.identity.getRedirectURL() 사용
    redirect_uri = params[:redirect_uri] || "https://sourcy.com/oauth/callback"

    query_params = { code: code }
    query_params[:state] = state if state.present?

    "#{redirect_uri}?#{query_params.to_query}"
  end

  # Chrome Extension callback URL with error
  def chrome_extension_callback_url_with_error(error, state)
    redirect_uri = params[:redirect_uri] || "https://sourcy.com/oauth/callback"

    query_params = { error: error }
    query_params[:state] = state if state.present?

    "#{redirect_uri}?#{query_params.to_query}"
  end
end
