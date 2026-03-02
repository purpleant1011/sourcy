# frozen_string_literal: true

Rails.application.routes.draw do
  root "dashboard#index"

  # Chrome Extension OAuth2
  get "auth/chrome_extension", to: "auth#chrome_extension", as: :chrome_extension_auth
  post "auth/chrome_extension/approve", to: "auth#chrome_extension_approve", as: :chrome_extension_approve
  post "auth/chrome_extension/deny", to: "auth#chrome_extension_deny", as: :chrome_extension_deny

  # Session
  resource :session
  resources :passwords, param: :token

  # Admin Dashboard
  namespace :admin do
    root to: 'dashboard#index'
    get 'stats', to: 'dashboard#stats'
    get 'activities', to: 'dashboard#activities'
    resources :orders
    resources :catalog_products
    resources :marketplace_listings
    resources :settlements do
      collection do
        get :report
        get :export
      end

      member do
        post :verify
      end
    end
    resource :settings, only: [:show, :update] do
      collection do
        post :create_credential
      end
      member do
        post :update_credential
        delete :destroy_credential
      end
    end
    resources :accounts, only: [:show, :update], controller: 'settings/accounts'
    resources :teams, only: [:index, :create, :update, :destroy], controller: 'settings/teams'
    resource :subscription, only: [:show, :update], controller: 'settings/subscriptions' do
      member do
        post :cancel
        post :resume
        post :change_plan
      end
    end
  end

  # API v1
  namespace :api do
    namespace :v1 do
      # Chrome Extension OAuth2 (PKCE)
      post "auth/authorize", to: "chrome_extension_auth#authorize"
      post "auth/token", to: "chrome_extension_auth#token"
      delete "auth/revoke", to: "chrome_extension_auth#revoke"
      get "auth/status", to: "chrome_extension_auth#status"

      # API Authentication (email/password)
      post "auth/login", to: "auth#login"
      post "auth/refresh", to: "auth#refresh"
      delete "auth/logout", to: "auth#logout"

      # Chrome Extension User
      get "user", to: "chrome_extension_user#show"
      put "user", to: "chrome_extension_user#update"
      put "user/account", to: "chrome_extension_user#update_account"

      # Chrome Extension Products
      post "products/extract", to: "chrome_extension_products#extract"
      get "products/stats", to: "chrome_extension_products#stats"
      resources :source_products, only: %i[index show update destroy], controller: "chrome_extension_products"

      # API Resources
      resources :source_products, only: %i[index create show] do
        collection do
          post :bulk_import
        end
      end

      resources :catalog_products, only: %i[index show update] do
        member do
          post :translate
        end

        collection do
          post :bulk_translate
        end
      end

      resources :marketplace_listings do
        member do
          post :publish
          post :validate
        end

        collection do
          post :bulk_publish
        end
      end

      resources :orders, only: %i[index show update] do
        member do
          post :confirm
          post :ship
        end

        resources :shipments, only: %i[index create show update], controller: "orders/shipments"
        resource :return_request, only: %i[show create update], controller: "orders/return_requests"
      end

      resource :analytics, only: [] do
        get :dashboard
        get :margin
      end

      resources :jobs, only: %i[show]

      resource :compliance, only: [], controller: :compliance do
        post :kc_check
        post :brand_check
        post :customs_estimate
      end
    end
  end

  # Webhooks
  namespace :webhooks do
    post :naver, to: "naver#create"
    post :coupang, to: "coupang#create"
    post :gmarket, to: "gmarket#create"
    post :elevenst, to: "elevenst#create"
    post :portone, to: "portone#create"
  end

  # Health Check
  get "up" => "rails/health#show", as: :rails_health_check
end
