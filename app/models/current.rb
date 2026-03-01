class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :account, :ip_address

  def session=(session)
    super
    self.user = session&.user
  end
end
