module Api
  module V1
    module Orders
      class ShipmentsController < BaseController
        def index
          render_success(data: order.shipments.order(created_at: :desc).as_json(include: :tracking_events))
        end

        def show
          shipment = order.shipments.find(params[:id])
          render_success(data: shipment.as_json(include: :tracking_events))
        end

        def create
          shipment = order.shipments.create!(shipment_params)
          render_success(data: shipment.as_json, status: :created)
        end

        def update
          shipment = order.shipments.find(params[:id])
          shipment.update!(shipment_params)
          render_success(data: shipment.as_json)
        end

        private

        def order
          @order ||= current_account_relation(Order).find(params[:order_id])
        end

        def shipment_params
          params.require(:shipment).permit(:shipping_provider, :tracking_number, :shipping_status, :shipping_cost_krw, :shipped_at, :delivered_at)
        end
      end
    end
  end
end
