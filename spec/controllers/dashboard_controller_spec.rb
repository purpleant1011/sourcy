# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardController, type: :controller do
  # DashboardController inherits from Admin::DashboardController
  # which requires basic authentication and uses admin layout

  describe "GET #index" do
    context "with valid basic auth" do
      it "returns http success" do
        request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "password")

        get :index

        expect(response).to have_http_status(:ok)
        expect(response).to render_template(:index)
      end
    end

    context "without basic auth" do
      it "returns unauthorized" do
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
