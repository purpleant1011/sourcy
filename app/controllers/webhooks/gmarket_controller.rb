module Webhooks
  class GmarketController < BaseController
    private

    def provider_key
      :gmarket
    end

    def verify_webhook_signature!
      verify_hmac_signature!(header: "X-Gmarket-Signature", credentials_key: :gmarket)
    end
  end
end
