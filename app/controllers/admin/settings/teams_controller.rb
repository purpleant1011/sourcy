# frozen_string_literal: true

# Team management controller for managing team members and roles
module Admin
  module Settings
    class TeamsController < ApplicationController
      before_action :set_account
      before_action :set_membership, only: [:update, :destroy]
      before_action :set_user, only: [:create]

      # Index team members
      def index
        @memberships = @account.memberships.includes(:user).order(:created_at)
        @pending_invites = @account.memberships.where(status: :pending)
      end

      # Create new team member
      def create
        @membership = @account.memberships.find_or_initialize_by(user: @user)

        if @membership.persisted?
          respond_to do |format|
            format.turbo_stream { render :error, locals: { message: '이미 팀에 속해 있습니다.' } }
            format.html { redirect_to admin_teams_path, alert: '이미 팀에 속해 있습니다.' }
          end
          return
        end

        @membership.assign_attributes(membership_params)
        @membership.role = params[:membership][:role] || :member
        @membership.status = :active
        @membership.invited_by = Current.user

        if @membership.save
          send_invitation_email(@membership) if params[:membership][:send_invitation] == '1'

          respond_to do |format|
            format.turbo_stream { render :create }
            format.html { redirect_to admin_teams_path, notice: '팀 멤버가 추가되었습니다.' }
          end
        else
          respond_to do |format|
            format.turbo_stream { render :create, status: :unprocessable_entity }
            format.html { render :index, status: :unprocessable_entity }
          end
        end
      end

      # Update team member role
      def update
        if @membership.update(membership_params)
          respond_to do |format|
            format.turbo_stream { render :update }
            format.html { redirect_to admin_teams_path, notice: '팀 멤버가 업데이트되었습니다.' }
          end
        else
          respond_to do |format|
            format.turbo_stream { render :update, status: :unprocessable_entity }
            format.html { render :index, status: :unprocessable_entity }
          end
        end
      end

      # Remove team member
      def destroy
        cannot_remove_owner! if @membership.role == 'owner' && @account.memberships.where(role: :owner).count == 1

        @membership.destroy

        respond_to do |format|
          format.turbo_stream { render :destroy }
          format.html { redirect_to admin_teams_path, notice: '팀 멤버가 제거되었습니다.' }
        end
      end

      private

      def set_account
        @account = Current.account
      end

      def set_membership
        @membership = @account.memberships.find(params[:id])
      end

      def set_user
        @user = User.find_by(email: params[:membership][:email])

        if @user.nil?
          respond_to do |format|
            format.turbo_stream { render :error, locals: { message: '사용자를 찾을 수 없습니다.' } }
            format.html { redirect_to admin_teams_path, alert: '사용자를 찾을 수 없습니다.' }
          end
        end
      end

      def membership_params
        params.require(:membership).permit(:role, :permissions => {})
      end

      def send_invitation_email(membership)
        # Send invitation email using ActionMailer
        # This would trigger an email with invitation link
        UserMailer.team_invitation(membership).deliver_later
      end

      def cannot_remove_owner!
        respond_to do |format|
          format.turbo_stream { render :error, locals: { message: '최소 한 명의 오너가 필요합니다.' } }
          format.html { redirect_to admin_teams_path, alert: '최소 한 명의 오너가 필요합니다.' }
        end
      end
    end
  end
end
