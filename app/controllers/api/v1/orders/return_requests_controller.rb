module Api
  module V1
    module Orders
      class ReturnRequestsController < BaseController
        def show
          return_request = order.return_request
          return render_error(code: "RESOURCE_NOT_FOUND", message: "Return request not found", status: :not_found) if return_request.blank?

          render_success(data: return_request.as_json)
        end

        def create
          return_request = order.create_return_request!(return_request_params.merge(requested_at: Time.current))
          render_success(data: return_request.as_json, status: :created)
        end

        def update
          return_request = order.return_request
          return render_error(code: "RESOURCE_NOT_FOUND", message: "Return request not found", status: :not_found) if return_request.blank?

          return_request.update!(return_request_params)
          render_success(data: return_request.as_json)
        end

        private

        def order
          @order ||= current_account_relation(Order).find(params[:order_id])
        end

        def return_request_params
          params.require(:return_request).permit(:reason_code, :reason_detail, :status, :refund_amount_krw, :resolved_at)
        end
      end
    end
  end
end
