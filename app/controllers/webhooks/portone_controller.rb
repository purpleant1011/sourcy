module Webhooks
  class PortoneController < BaseController
    private

    def provider_key
      :portone
    end

    def verify_webhook_signature!
      verify_hmac_signature!(header: "X-Portone-Signature", credentials_key: :portone)
    end
  end
end
