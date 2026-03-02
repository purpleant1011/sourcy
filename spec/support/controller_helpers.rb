# frozen_string_literal: true

# Controller test helpers for authentication and session management
module ControllerHelpers
  def sign_in(user)
    session_record = Session.create!(
      user: user,
      user_agent: "RSpec Test",
      ip_address: "127.0.0.1",
      expires_at: 24.hours.from_now
    )

    cookies.signed["session_id"] = session_record.signed_id
    Current.user = user
    Current.session = session_record
  end

  def sign_out
    session_id = cookies.signed["session_id"]
    session_record = Session.find_signed_by_id(session_id) if session_id

    session_record&.destroy
    cookies.delete("session_id")
    Current.reset
  end
end
