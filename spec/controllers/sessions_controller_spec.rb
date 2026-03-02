# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionsController, type: :controller do
  describe "GET #new" do
    it "returns http success" do
      get :new
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST #create" do
    let(:user) { create(:user, email: "test@example.com", password: "Password123!") }

    context "with valid credentials" do
      it "authenticates user and starts new session" do
        post :create, params: { email: "test@example.com", password: "Password123!" }

        expect(response).to redirect_to(root_path)
        expect(cookies.signed["session_id"]).to be_present
        expect(session[:user_id]).to eq(user.id)
      end

      it "sets Current.user and Current.session" do
        post :create, params: { email: "test@example.com", password: "Password123!" }

        expect(Current.user).to eq(user)
        expect(Current.session).to be_present
      end
    end

    context "with invalid credentials" do
      it "does not authenticate user" do
        post :create, params: { email: "test@example.com", password: "WrongPassword!" }

        expect(response).to redirect_to(new_session_path)
        expect(cookies.signed["session_id"]).to be_nil
      end

      it "sets alert message" do
        post :create, params: { email: "test@example.com", password: "WrongPassword!" }

        expect(flash[:alert]).to eq("Try another email address or password.")
      end
    end

    context "with rate limiting" do
      before do
        10.times do
          post :create, params: { email: "test@example.com", password: "WrongPassword!" }
        end
      end

      it "enforces rate limit after 10 failed attempts" do
        post :create, params: { email: "test@example.com", password: "Password123!" }

        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to include("Try again later")
      end
    end
  end

  describe "DELETE #destroy" do
    let(:user) { create(:user) }
    let(:session_record) { create(:session, user: user) }

    before do
      cookies.signed["session_id"] = session_record.signed_id
      Current.session = session_record
      Current.user = user
    end

    it "terminates session" do
      expect {
        delete :destroy
      }.to change(Session, :count).by(-1)
    end

    it "clears cookies" do
      delete :destroy

      expect(cookies.signed["session_id"]).to be_nil
    end

    it "redirects to new session path with 303 status" do
      delete :destroy

      expect(response).to redirect_to(new_session_path)
      expect(response.status).to eq(303) # HTTP 303 See Other
    end
  end
end
