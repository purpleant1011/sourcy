begin
  require "omniauth-google-oauth2"
rescue LoadError
end

begin
  require "omniauth-kakao"
rescue LoadError
  begin
    require "omniauth/kakao"
  rescue LoadError
  end
end

begin
  require "omniauth-naver"
rescue LoadError
  begin
    require "omniauth/naver"
  rescue LoadError
  end
end

Rails.application.config.middleware.use OmniAuth::Builder do
  if defined?(OmniAuth::Strategies::Kakao)
    provider :kakao,
             Rails.application.credentials.dig(:oauth, :kakao, :client_id),
             Rails.application.credentials.dig(:oauth, :kakao, :client_secret)
  end

  if defined?(OmniAuth::Strategies::Naver)
    provider :naver,
             Rails.application.credentials.dig(:oauth, :naver, :client_id),
             Rails.application.credentials.dig(:oauth, :naver, :client_secret)
  end

  if defined?(OmniAuth::Strategies::GoogleOauth2)
    provider :google_oauth2,
             Rails.application.credentials.dig(:oauth, :google, :client_id),
             Rails.application.credentials.dig(:oauth, :google, :client_secret),
             {
               scope: "email profile",
               prompt: "select_account"
             }
  end
end
