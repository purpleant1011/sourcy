class ApplicationController < ActionController::Base
  include Authentication
  before_action :authenticate
  before_action :set_current_context
  before_action :set_current_account

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def set_current_context
    Current.ip_address = request.remote_ip
    Current.user ||= Current.session&.user
  end

  def set_current_account
    Current.account = Current.user&.account
  end
end
