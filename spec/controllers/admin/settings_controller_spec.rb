# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SettingsController", type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    Current.account = account
    Current.user = user
    sign_in user
  end

  describe "GET #show" do
    it "assigns account, memberships and api_credentials" do
      create(:membership, account: account, user: user)
      create(:api_credential, account: account)

      get :show

      expect(assigns(:account)).to eq(account)
      expect(assigns(:memberships)).to include(account.memberships.first)
      expect(assigns(:api_credentials)).to eq(account.api_credentials)
    end
  end

  describe "PATCH #update" do
    context "with valid params" do
      it "updates account" do
        patch :update, params: {
          account: {
            name: "Updated Name",
            company_name: "Updated Company"
          }
        }

        expect(account.reload.name).to eq("Updated Name")
        expect(response).to redirect_to(admin_settings_path)
        expect(flash[:notice]).to eq("계정 설정이 저장되었습니다.")
      end
    end

    context "with invalid params" do
      it "renders show template with unprocessable_entity" do
        patch :update, params: {
          account: { name: "" }
        }

        expect(response).to render_template(:show)
        expect(response.status).to eq(:unprocessable_entity)
      end
    end
  end

  describe "POST #create_credential" do
    context "with valid params" do
      it "creates new api credential" do
        expect {
          post :create_credential, params: {
            api_credential: {
              provider: "naver",
              access_key: "test_key",
              secret_key: "test_secret"
            }
          }
        }.to change(account.api_credentials, :count).by(1)

        expect(response).to redirect_to(admin_settings_path)
        expect(flash[:notice]).to eq("API 자격 증명이 추가되었습니다.")
      end
    end

    context "with invalid params" do
      it "renders show template with unprocessable_entity" do
        post :create_credential, params: {
          api_credential: { provider: "" }
        }

        expect(response).to render_template(:show)
        expect(response.status).to eq(:unprocessable_entity)
      end
    end
  end

  describe "PATCH #update_credential" do
    let(:credential) { create(:api_credential, account: account) }

    context "with valid params" do
      it "updates api credential" do
        patch :update_credential, params: {
          id: credential.id,
          api_credential: { access_key: "new_key" }
        }

        expect(credential.reload.access_key).to eq("new_key")
        expect(response).to redirect_to(admin_settings_path)
        expect(flash[:notice]).to eq("API 자격 증명이 업데이트되었습니다.")
      end
    end

    context "with invalid params" do
      it "renders show template with unprocessable_entity" do
        patch :update_credential, params: {
          id: credential.id,
          api_credential: { access_key: "" }
        }

        expect(response).to render_template(:show)
        expect(response.status).to eq(:unprocessable_entity)
      end
    end
  end

  describe "DELETE #destroy_credential" do
    let(:credential) { create(:api_credential, account: account) }

    it "destroys api credential" do
      expect {
        delete :destroy_credential, params: { id: credential.id }
      }.to change(ApiCredential, :count).by(-1)

      expect(response).to redirect_to(admin_settings_path)
      expect(flash[:notice]).to eq("API 자격 증명이 삭제되었습니다.")
    end
  end
end
