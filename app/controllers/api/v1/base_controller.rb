module Api
  module V1
    class BaseController < ActionController::API
      include Pagy::Backend

      before_action :authenticate_api!
      before_action :require_idempotency_key!, if: :mutation_request?
      after_action :set_rate_limit_headers

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found_error
      rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid_error
      rescue_from ActiveRecord::RecordNotUnique, with: :render_record_not_unique_error
      rescue_from ActionController::ParameterMissing, with: :render_parameter_missing_error
      rescue_from JWT::DecodeError, JWT::ExpiredSignature, with: :render_invalid_token_error

      private

      def render_success(data:, status: :ok, meta: nil)
        payload = { success: true, data: data }
        payload[:meta] = meta if meta.present?
        render json: payload, status: status
      end

      def render_error(code:, message:, status:, details: {})
        render json: {
          success: false,
          error: {
            code: code,
            message: message,
            details: details
          }
        }, status: status
      end

      def authenticate_api!
        token = bearer_token
        return render_error(code: "AUTH_MISSING_TOKEN", message: "Authorization token is required", status: :unauthorized) if token.blank?

        payload = decode_jwt!(token)
        user = User.find_by(id: payload["sub"])
        account = Account.find_by(id: payload["account_id"])
        session = Session.find_by(id: payload["sid"])

        if user.blank? || account.blank? || session.blank? || user.account_id != account.id || session.user_id != user.id
          return render_error(code: "AUTH_INVALID_TOKEN", message: "Token is invalid", status: :unauthorized)
        end

        Current.user = user
        Current.account = account
        Current.session = session
        Current.ip_address = request.remote_ip
      end

      def current_account_relation(model_class)
        model_class.where(account_id: Current.account.id)
      end

      def cursor_paginate(scope, order_column: :created_at)
        per_page = params.fetch(:per_page, 25).to_i.clamp(1, 100)
        relation = scope.order(order_column => :desc, id: :desc)
        relation = apply_cursor(relation, order_column)
        records = relation.limit(per_page + 1).to_a
        next_record = records[per_page]

        pagy = Pagy.new(count: records.first(per_page).size, page: 1, limit: per_page)
        [
          records.first(per_page),
          {
            page: pagy.page,
            per_page: pagy.limit,
            total: nil,
            next_cursor: next_record ? encode_cursor(next_record, order_column) : nil
          }
        ]
      end

      def encode_cursor(record, order_column)
        payload = {
          id: record.id,
          order_value: record.public_send(order_column).iso8601(6)
        }
        Base64.urlsafe_encode64(payload.to_json)
      end

      def decode_cursor(order_column)
        return if params[:cursor].blank?

        parsed = JSON.parse(Base64.urlsafe_decode64(params[:cursor]))
        {
          id: parsed.fetch("id"),
          order_value: Time.iso8601(parsed.fetch("order_value")),
          order_column: order_column
        }
      rescue JSON::ParserError, ArgumentError, KeyError
        render_error(code: "PAGINATION_INVALID_CURSOR", message: "Cursor is invalid", status: :unprocessable_entity)
        nil
      end

      def apply_cursor(relation, order_column)
        cursor = decode_cursor(order_column)
        return relation if cursor.nil? || performed?

        relation.where(
          "#{order_column} < :order_value OR (#{order_column} = :order_value AND id < :id)",
          order_value: cursor[:order_value],
          id: cursor[:id]
        )
      end

      def require_idempotency_key!
        return if request.headers["X-Idempotency-Key"].present? || request.headers["Idempotency-Key"].present?

        render_error(
          code: "IDEMPOTENCY_KEY_REQUIRED",
          message: "Idempotency key is required for mutation requests",
          status: :unprocessable_entity
        )
      end

      def mutation_request?
        request.post? || request.put? || request.patch? || request.delete?
      end

      def set_rate_limit_headers
        response.set_header("X-RateLimit-Limit", request.env["rack.attack.limit"]) if request.env["rack.attack.limit"].present?
        response.set_header("X-RateLimit-Remaining", request.env["rack.attack.remaining"]) if request.env["rack.attack.remaining"].present?
        response.set_header("X-RateLimit-Reset", request.env["rack.attack.reset_time"].to_i) if request.env["rack.attack.reset_time"].present?
      end

      def decode_jwt!(token)
        JWT.decode(token, jwt_secret, true, algorithm: "HS256").first
      end

      def jwt_secret
        Rails.application.credentials.jwt_secret || Rails.application.secret_key_base
      end

      def bearer_token
        header = request.headers["Authorization"].to_s
        return if header.blank?

        scheme, token = header.split(" ", 2)
        return if scheme != "Bearer"

        token
      end

      def render_not_found_error(error)
        render_error(code: "RESOURCE_NOT_FOUND", message: error.message, status: :not_found)
      end

      def render_record_invalid_error(error)
        render_error(
          code: "VALIDATION_FAILED",
          message: "Validation failed",
          status: :unprocessable_entity,
          details: error.record.errors.to_hash
        )
      end

      def render_record_not_unique_error(_error)
        render_error(code: "RESOURCE_CONFLICT", message: "Resource already exists", status: :conflict)
      end

      def render_parameter_missing_error(error)
        render_error(code: "INVALID_REQUEST", message: error.message, status: :bad_request)
      end

      def render_invalid_token_error(_error)
        render_error(code: "AUTH_INVALID_TOKEN", message: "Token is invalid or expired", status: :unauthorized)
      end
    end
  end
end
