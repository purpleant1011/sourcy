require Rails.root.join("app/middleware/idempotency")

Rails.application.config.middleware.insert_before Rack::Attack, Idempotency
