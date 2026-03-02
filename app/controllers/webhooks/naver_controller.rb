module Webhooks
  class NaverController < BaseController
    private

    def provider_key
      :naver_smartstore
    end

    def verify_webhook_signature!
      verify_hmac_signature!(header: "X-Naver-Signature", credentials_key: :naver_smartstore)
    end
  end
end
