source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"

# Use Active Model has_secure_password
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma
gem "thruster", require: false

# Use Active Storage variants
gem "image_processing", "~> 1.2"

# === Sourcy PRD Dependencies ===

# Authentication & OAuth
gem "omniauth", "~> 2.1"
gem "omniauth-rails_csrf_protection", "~> 1.0"
gem "omniauth-kakao"
gem "omniauth-naver"
gem "omniauth-google-oauth2", "~> 1.1"
gem "jwt", "~> 2.8"
gem "rotp", "~> 6.3"
gem "rqrcode", "~> 2.2"

# Authorization
gem "pundit", "~> 2.4"

# HTTP Client
gem "httpx"

# Excel/CSV parsing
gem "roo", "~> 2.10"

# Charts
gem "chartkick"
gem "groupdate"

# Pagination
gem "pagy", "~> 9.0"

# Rate limiting
gem "rack-attack"

# Payment (PortOne API calls)
gem "httparty"

# Image processing (ruby-vips)
gem "ruby-vips", "~> 2.2"

# Google Cloud Services (Add credentials to Rails credentials to enable)
# gem "google-cloud-vision", "~> 2.0"
# gem "google-cloud-translate", "~> 2.0"
# Monitoring
gem "google-cloud-translate", "~> 2.0"

# Monitoring
gem "sentry-ruby"
gem "sentry-rails"

# Mission Control (Solid Queue dashboard)
gem "mission_control-jobs"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities
  gem "brakeman", require: false

  # Omakase Ruby styling
  gem "rubocop-rails-omakase", require: false

  # Testing
  gem "factory_bot_rails"
  gem "rails-controller-testing"
  gem "faker"
  gem "rspec-rails", "~> 8.0"
  gem "shoulda-matchers"
end

group :development do
  # Use console on exceptions pages
  gem "web-console"
  gem "letter_opener"
  gem "annotaterb"
end

group :test do
  # Use system testing
  gem "capybara"
  gem "selenium-webdriver"
end
