# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuthController, type: :controller do
  let(:auth_session_id) { SecureRandom.hex(16) }
  let(:auth_session) do
    {
      session_id: auth_session_id,
      code_challenge: "test_challenge",
      code_challenge_method: "S256",
      state: "test_state"
    }
  end

  describe "GET #chrome_extension" do
    context "with valid auth session" do
      before do
        Rails.cache.write("oauth_auth:#{auth_session_id}", auth_session, expires_in: 10.minutes)
      end

      context "when user is already logged in" do
        let(:user) { create(:user) }

        before do
          sign_in(user)
        end

        it "renders chrome_extension_authorize template" do
          get :chrome_extension, params: { session_id: auth_session_id }

          expect(response).to render_template(:chrome_extension_authorize)
          expect(assigns(:auth_session)).to eq(auth_session)
        end
      end

      context "when user is not logged in" do
        it "stores oauth_redirect in session" do
          get :chrome_extension, params: { session_id: auth_session_id }

          expect(session[:oauth_redirect]).to eq(chrome_extension_auth_path(session_id: auth_session_id))
        end

        it "redirects to new_session_path" do
          get :chrome_extension, params: { session_id: auth_session_id }

          expect(response).to redirect_to(new_session_path)
        end
      end
    end

    context "with invalid or expired auth session" do
      it "renders chrome_extension_error template" do
        get :chrome_extension, params: { session_id: "invalid_session_id" }

        expect(response).to render_template(:chrome_extension_error)
        expect(response).to have_http_status(:bad_request)
        expect(assigns(:error)).to eq("Authorization session has expired. Please try again from Chrome Extension.")
      end
    end
  end

  describe "POST #chrome_extension_approve" do
    let(:user) { create(:user) }

    before do
      Rails.cache.write("oauth_auth:#{auth_session_id}", auth_session, expires_in: 10.minutes)
      sign_in(user)
    end

    context "with valid auth session and logged in user" do
      it "generates and stores authorization code" do
        post :chrome_extension_approve, params: { session_id: auth_session_id }

        code = assigns(:code)
        expect(code).to be_present
        expect(code.length).to eq(64)
      end

      it "stores authorization code in cache" do
        post :chrome_extension_approve, params: { session_id: auth_session_id }

        code = assigns(:code)
        cached_data = Rails.cache.read("oauth_code:#{code}")

        expect(cached_data).to be_present
        expect(cached_data[:user_id]).to eq(user.id)
        expect(cached_data[:session_id]).to eq(auth_session_id)
        expect(cached_data[:code_challenge]).to eq("test_challenge")
      end

      it "redirects to Chrome Extension callback URL with code" do
        post :chrome_extension_approve, params: { session_id: auth_session_id, redirect_uri: "https://example.com/callback" }

        expect(response).to redirect_to(%r{^https://example\.com/callback\?code=.*$})
      end
    end

    context "with invalid auth session" do
      it "redirects with error" do
        post :chrome_extension_approve, params: { session_id: "invalid_session_id" }

        expect(response).to redirect_to(chrome_extension_auth_path(session_id: "invalid_session_id"))
        expect(flash[:alert]).to eq("Authorization session has expired")
      end
    end

    context "without logged in user" do
      before do
        sign_out(user)
      end

      it "redirects with error" do
        post :chrome_extension_approve, params: { session_id: auth_session_id }

        expect(response).to redirect_to(chrome_extension_auth_path(session_id: auth_session_id))
        expect(flash[:alert]).to eq("You must be logged in to authorize")
      end
    end
  end

  describe "POST #chrome_extension_deny" do
    before do
      Rails.cache.write("oauth_auth:#{auth_session_id}", auth_session, expires_in: 10.minutes)
    end

    it "deletes auth session from cache" do
      post :chrome_extension_deny, params: { session_id: auth_session_id, state: "test_state" }

      expect(Rails.cache.read("oauth_auth:#{auth_session_id}")).to be_nil
    end

    it "redirects to callback URL with access_denied error" do
      post :chrome_extension_deny, params: { session_id: auth_session_id, state: "test_state", redirect_uri: "https://example.com/callback" }

      expect(response).to redirect_to(%r{^https://example\.com/callback\?error=access_denied})
    end
  end

  private

  def sign_in(user)
    session = create(:session, user: user)
    cookies.signed["session_id"] = session.signed_id
    Current.session = session
    Current.user = user
  end

  def sign_out(user)
    Current.session = nil
    Current.user = nil
    cookies.delete("session_id")
  end
end
