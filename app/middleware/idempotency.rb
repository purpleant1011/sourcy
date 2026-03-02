class Idempotency
  CACHE_TTL = 24.hours
  MUTATION_METHODS = %w[ POST PUT PATCH DELETE ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    return @app.call(env) unless eligible_request?(request)

    key = request.headers["Idempotency-Key"].presence || request.headers["X-Idempotency-Key"].presence
    return @app.call(env) if key.blank?

    cache_key = cache_key_for(request, key)
    cached = Rails.cache.read(cache_key)

    if cached.present?
      headers = cached[:headers].merge("X-Idempotency-Replayed" => "true")
      return [ cached[:status], headers, [ cached[:body] ] ]
    end

    status, headers, body = @app.call(env)
    body_content = body_to_string(body)
    body.close if body.respond_to?(:close)

    Rails.cache.write(
      cache_key,
      { status: status, headers: cacheable_headers(headers), body: body_content },
      expires_in: CACHE_TTL
    )

    [ status, headers, [ body_content ] ]
  end

  private

  def eligible_request?(request)
    request.path.start_with?("/api/v1") && MUTATION_METHODS.include?(request.request_method)
  end

  def cache_key_for(request, idempotency_key)
    body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
    "idempotency:#{request.request_method}:#{request.path}:#{idempotency_key}:#{body_hash}"
  end

  def body_to_string(body)
    content = +""
    body.each { |chunk| content << chunk.to_s }
    content
  end

  def cacheable_headers(headers)
    headers.to_h.slice("Content-Type", "Cache-Control")
  end
end
