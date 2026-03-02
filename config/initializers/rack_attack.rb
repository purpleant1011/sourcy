class Rack::Attack
  LOGIN_PATH = "/api/v1/auth/login".freeze

  throttle("login/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == LOGIN_PATH && req.post?
  end

  throttle("api/basic", limit: 100, period: 1.minute) do |req|
    next unless req.path.start_with?("/api/v1")

    account_rate_key(req, :basic)
  end

  throttle("api/pro", limit: 500, period: 1.minute) do |req|
    next unless req.path.start_with?("/api/v1")

    account_rate_key(req, :pro)
  end

  throttle("api/premium", limit: 2000, period: 1.minute) do |req|
    next unless req.path.start_with?("/api/v1")

    account_rate_key(req, :premium)
  end

  throttle("webhooks/provider_ip", limit: 1000, period: 1.minute) do |req|
    next unless req.path.start_with?("/webhooks/")

    provider = req.path.split("/")[2]
    "#{provider}:#{req.ip}"
  end

  self.throttled_responder = lambda do |request|
    now = Time.current
    match_data = request.env["rack.attack.match_data"] || {}

    headers = {
      "Content-Type" => "application/json",
      "X-RateLimit-Limit" => match_data[:limit].to_s,
      "X-RateLimit-Remaining" => "0",
      "X-RateLimit-Reset" => (now + (match_data[:period] || 60)).to_i.to_s
    }

    body = {
      success: false,
      error: {
        code: "RATE_LIMITED",
        message: "Too many requests",
        details: {
          path: request.path,
          throttle: request.env["rack.attack.matched"]
        }
      }
    }.to_json

    [ 429, headers, [ body ] ]
  end

  def self.account_rate_key(req, expected_plan)
    token = bearer_token(req)
    return unless token

    payload = decode_token(token)
    return unless payload

    account = Account.find_by(id: payload["account_id"])
    return unless account&.plan&.to_sym == expected_plan

    "#{account.id}:#{req.ip}"
  end

  def self.bearer_token(req)
    header = req.get_header("HTTP_AUTHORIZATION").to_s
    scheme, token = header.split(" ", 2)
    scheme == "Bearer" ? token : nil
  end

  def self.decode_token(token)
    secret = Rails.application.credentials.jwt_secret || Rails.application.secret_key_base
    JWT.decode(token, secret, true, algorithm: "HS256").first
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end

Rails.application.config.middleware.use Rack::Attack
