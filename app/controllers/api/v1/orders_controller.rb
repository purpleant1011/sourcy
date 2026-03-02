module Api
  module V1
    class OrdersController < BaseController
      def index
        records, meta = cursor_paginate(current_account_relation(Order), order_column: :ordered_at)
        render_success(data: records.as_json(include: %i[order_items shipments return_request]), meta: meta)
      end

      def show
        order = current_account_relation(Order).find(params[:id])
        render_success(data: order.as_json(include: %i[order_items shipments return_request]))
      end

      def update
        order = current_account_relation(Order).find(params[:id])
        order.update!(order_params)
        render_success(data: order.as_json)
      end

      def confirm
        order = current_account_relation(Order).find(params[:id])
        order.update!(order_status: :preparing)
        render_success(data: { id: order.id, order_status: order.order_status })
      end

      def ship
        order = current_account_relation(Order).find(params[:id])
        shipment = order.shipments.create!(shipment_params)
        order.update!(order_status: :shipped)
        render_success(data: { order: order.as_json, shipment: shipment.as_json })
      end

      private

      def order_params
        params.require(:order).permit(:order_status, :shipping_memo)
      end

      def shipment_params
        params.fetch(:shipment, {}).permit(
          :shipping_provider,
          :tracking_number,
          :shipping_status,
          :shipping_cost_krw,
          :shipped_at,
          :delivered_at
        )
      end
    end
  end
end
