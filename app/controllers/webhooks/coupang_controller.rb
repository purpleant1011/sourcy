module Webhooks
  class CoupangController < BaseController
    private

    def provider_key
      :coupang
    end

    def verify_webhook_signature!
      verify_hmac_signature!(header: "X-Coupang-Signature", credentials_key: :coupang)
    end
  end
end
