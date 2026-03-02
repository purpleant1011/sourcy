module Webhooks
  class ElevenstController < BaseController
    private

    def provider_key
      :eleven_street
    end

    def verify_webhook_signature!
      verify_hmac_signature!(header: "X-11st-Signature", credentials_key: :eleven_street)
    end
  end
end
