module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate_api!, only: %i[login refresh]
      skip_before_action :require_idempotency_key!, only: %i[login refresh]

      def login
        user = User.authenticate_by(email: login_params[:email], password: login_params[:password])
        return render_error(code: "AUTH_INVALID_CREDENTIALS", message: "Email or password is invalid", status: :unauthorized) if user.blank?

        session = create_api_session(user)
        token_payload = issue_tokens_for(session)

        render_success(data: token_payload)
      end

      def refresh
        old_session = Session.find_signed_by_id(refresh_params[:refresh_token], purpose: "api_refresh")
        return render_error(code: "AUTH_REFRESH_TOKEN_INVALID", message: "Refresh token is invalid", status: :unauthorized) if old_session.blank?

        user = old_session.user
        old_session.destroy!

        new_session = create_api_session(user)
        render_success(data: issue_tokens_for(new_session))
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        render_error(code: "AUTH_REFRESH_TOKEN_INVALID", message: "Refresh token is invalid", status: :unauthorized)
      end

      def logout
        Current.session&.destroy!
        Current.reset
        render_success(data: { revoked: true })
      end

      private

      def login_params
        params.permit(:email, :password)
      end

      def refresh_params
        params.permit(:refresh_token)
      end

      def create_api_session(user)
        user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip)
      end

      def issue_tokens_for(session)
        user = session.user
        expires_at = 15.minutes.from_now
        payload = {
          sub: user.id,
          account_id: user.account_id,
          sid: session.id,
          iat: Time.current.to_i,
          exp: expires_at.to_i
        }

        {
          jwt: JWT.encode(payload, jwt_secret, "HS256"),
          refresh_token: session.signed_id(purpose: "api_refresh", expires_in: 30.days),
          expires_at: expires_at.to_i,
          user: {
            id: user.id,
            email: user.email,
            name: user.name,
            role: user.role,
            account_id: user.account_id
          }
        }
      end
    end
  end
end
