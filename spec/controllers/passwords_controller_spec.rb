# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordsController, type: :controller do
  let(:user) { create(:user, email: "test@example.com", password: "OldPassword123!") }

  describe "GET #new" do
    it "returns http success" do
      get :new
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST #create" do
    context "with existing email" do
      it "sends password reset email" do
        expect {
          post :create, params: { email: "test@example.com" }
        }.to have_enqueued_job(ActionMailer::MailDeliveryJob).with("PasswordsMailer", "reset", "deliver_now", hash_including(:args))

        expect(response).to redirect_to(new_session_path)
        expect(flash[:notice]).to eq("Password reset instructions sent (if user with that email address exists).")
      end
    end

    context "with non-existing email" do
      it "does not send email" do
        expect {
          post :create, params: { email: "nonexistent@example.com" }
        }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)

        expect(response).to redirect_to(new_session_path)
        expect(flash[:notice]).to eq("Password reset instructions sent (if user with that email address exists).")
      end
    end

    context "with rate limiting" do
      before do
        10.times do
          post :create, params: { email: "test@example.com" }
        end
      end

      it "enforces rate limit after 10 attempts" do
        post :create, params: { email: "test@example.com" }

        expect(response).to redirect_to(new_password_path)
        expect(flash[:alert]).to include("Try again later")
      end
    end
  end

  describe "GET #edit" do
    context "with valid token" do
      let(:token) { user.generate_password_reset_token }

      it "returns http success" do
        get :edit, params: { token: token }

        expect(response).to have_http_status(:ok)
        expect(assigns(:user)).to eq(user)
      end
    end

    context "with invalid or expired token" do
      it "redirects with error" do
        get :edit, params: { token: "invalid_token" }

        expect(response).to redirect_to(new_password_path)
        expect(flash[:alert]).to eq("Password reset link is invalid or has expired.")
      end
    end
  end

  describe "PATCH #update" do
    let(:token) { user.generate_password_reset_token }

    context "with valid password" do
      it "updates user password" do
        patch :update, params: {
          token: token,
          password: "NewPassword123!",
          password_confirmation: "NewPassword123!"
        }

        expect(user.reload.authenticate("NewPassword123!")).to eq(user)
      end

      it "destroys all user sessions" do
        create(:session, user: user)
        create(:session, user: user)

        expect {
          patch :update, params: {
            token: token,
            password: "NewPassword123!",
            password_confirmation: "NewPassword123!"
          }
        }.to change(user.sessions, :count).by(-2)
      end

      it "redirects to new session path" do
        patch :update, params: {
          token: token,
          password: "NewPassword123!",
          password_confirmation: "NewPassword123!"
        }

        expect(response).to redirect_to(new_session_path)
        expect(flash[:notice]).to eq("Password has been reset.")
      end
    end

    context "with invalid password" do
      it "does not update user password" do
        patch :update, params: {
          token: token,
          password: "New",
          password_confirmation: "New"
        }

        expect(user.reload.authenticate("New")).not_to eq(user)
      end

      it "redirects with error" do
        patch :update, params: {
          token: token,
          password: "New",
          password_confirmation: "New"
        }

        expect(response).to redirect_to(edit_password_path(token))
        expect(flash[:alert]).to eq("Passwords did not match.")
      end
    end
  end
end
