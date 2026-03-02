# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Settings::TeamsController", type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    Current.account = account
    Current.user = user
    sign_in user
  end

  describe "GET #index" do
    it "assigns memberships" do
      create(:membership, account: account, user: user)
      create(:membership, account: account)

      get :index

      expect(assigns(:memberships)).to include(account.memberships)
    end
  end

  describe "POST #create" do
    context "with existing user" do
      let(:existing_user) { create(:user) }

      context "user already in team" do
        before do
          create(:membership, account: account, user: existing_user)
        end

        it "returns error" do
          post :create, params: {
            membership: { email: existing_user.email, role: :member }
          }

          expect(response).to render_template(:error)
        end
      end

      context "user not in team" do
        it "creates new membership" do
          expect {
            post :create, params: {
              membership: { email: existing_user.email, role: :member }
            }
          }.to change(account.memberships, :count).by(1)

          expect(response).to render_template(:create)
        end

        it "sends invitation email if requested" do
          expect {
            post :create, params: {
              membership: { email: existing_user.email, role: :member, send_invitation: '1' }
            }
          }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
        end
      end
    end

    context "with non-existing user" do
      it "returns error" do
        post :create, params: {
          membership: { email: "nonexistent@example.com", role: :member }
        }

        expect(response).to render_template(:error)
      end
    end
  end

  describe "PATCH #update" do
    let(:membership) { create(:membership, account: account, role: :member) }

    context "with valid params" do
      it "updates membership role" do
        patch :update, params: {
          id: membership.id,
          membership: { role: :admin }
        }

        expect(membership.reload.role).to eq("admin")
        expect(response).to render_template(:update)
      end
    end

    context "with invalid params" do
      it "renders error with unprocessable_entity" do
        patch :update, params: {
          id: membership.id,
          membership: { role: :invalid_role }
        }

        expect(response).to render_template(:update)
        expect(response.status).to eq(:unprocessable_entity)
      end
    end
  end

  describe "DELETE #destroy" do
    let(:membership) { create(:membership, account: account, role: :member) }

    it "destroys membership" do
      expect {
        delete :destroy, params: { id: membership.id }
      }.to change(account.memberships, :count).by(-1)

      expect(response).to render_template(:destroy)
    end

    context "when trying to remove last owner" do
      let(:owner_membership) { create(:membership, account: account, role: :owner) }

      before do
        membership.destroy
      end

      it "returns error" do
        delete :destroy, params: { id: owner_membership.id }

        expect(response).to render_template(:error)
        expect(owner_membership.reload).to be_persisted
      end
    end
  end
end
