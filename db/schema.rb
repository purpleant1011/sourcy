# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_02_014619) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "owner_id"
    t.integer "plan", default: 0, null: false
    t.jsonb "settings", default: {}, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_accounts_on_owner_id"
    t.index ["plan"], name: "index_accounts_on_plan"
    t.index ["slug"], name: "index_accounts_on_slug", unique: true
  end

  create_table "alerts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "severity"
    t.string "source"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "api_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "secret_key_digest", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id", "expires_at"], name: "index_api_credentials_on_account_id_and_expires_at"
    t.index ["account_id", "user_id"], name: "index_api_credentials_on_account_id_and_user_id"
    t.index ["account_id"], name: "index_api_credentials_on_account_id"
    t.index ["user_id"], name: "index_api_credentials_on_user_id"
  end

  create_table "audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action", null: false
    t.jsonb "audit_changes", default: {}, null: false
    t.uuid "auditable_id", null: false
    t.string "auditable_type", null: false
    t.datetime "created_at", null: false
    t.inet "ip_address"
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["account_id", "action"], name: "index_audit_logs_on_account_id_and_action"
    t.index ["account_id", "auditable_type", "auditable_id"], name: "idx_on_account_id_auditable_type_auditable_id_a9dac8a799"
    t.index ["account_id", "created_at"], name: "index_audit_logs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_audit_logs_on_account_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "brand_filters", force: :cascade do |t|
    t.integer "action", default: 0, null: false
    t.string "brand_name", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.string "keyword", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_brand_filters_on_action"
    t.index ["keyword", "category"], name: "index_brand_filters_on_keyword_and_category", unique: true
  end

  create_table "catalog_products", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.bigint "base_price_krw", null: false
    t.jsonb "category_tags", default: [], null: false
    t.bigint "cost_price_krw", null: false
    t.datetime "created_at", null: false
    t.decimal "customs_duty_rate", precision: 6, scale: 3
    t.decimal "fx_rate_snapshot", precision: 12, scale: 4, null: false
    t.string "hs_code"
    t.boolean "kc_cert_required", default: false, null: false
    t.integer "kc_cert_status", default: 0, null: false
    t.decimal "margin_percent", precision: 6, scale: 2, null: false
    t.jsonb "processed_images", default: [], null: false
    t.jsonb "risk_flags", default: {}, null: false
    t.uuid "source_product_id", null: false
    t.integer "status", default: 0, null: false
    t.text "translated_description"
    t.string "translated_title", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('simple'::regconfig, (COALESCE(translated_title, ''::character varying))::text)", name: "index_catalog_products_on_translated_title_tsv", using: :gin
    t.index ["account_id", "status"], name: "index_catalog_products_on_account_id_and_status"
    t.index ["account_id"], name: "index_catalog_products_on_account_id"
    t.index ["risk_flags"], name: "index_catalog_products_on_risk_flags", using: :gin
    t.index ["source_product_id"], name: "index_catalog_products_on_source_product_id", unique: true
  end

  create_table "category_mappings", force: :cascade do |t|
    t.uuid "account_id", null: false
    t.jsonb "attribute_mappings", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "source_category", null: false
    t.string "target_category_code", null: false
    t.string "target_category_name"
    t.integer "target_marketplace", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "source_category", "target_marketplace"], name: "idx_category_mappings_unique", unique: true
    t.index ["account_id", "target_marketplace"], name: "index_category_mappings_on_account_id_and_target_marketplace"
    t.index ["account_id"], name: "index_category_mappings_on_account_id"
  end

  create_table "commission_rates", force: :cascade do |t|
    t.string "category_code", null: false
    t.string "category_name", null: false
    t.datetime "created_at", null: false
    t.date "effective_from", null: false
    t.date "effective_until"
    t.integer "marketplace_platform", null: false
    t.decimal "rate_percent", precision: 6, scale: 3, null: false
    t.datetime "updated_at", null: false
    t.index ["marketplace_platform", "category_code", "effective_from"], name: "idx_commission_rates_unique_window", unique: true
  end

  create_table "extraction_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.string "input_hash", null: false
    t.integer "provider", null: false
    t.jsonb "result", default: {}, null: false
    t.uuid "source_product_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "input_hash"], name: "index_extraction_runs_on_provider_and_input_hash"
    t.index ["source_product_id", "created_at"], name: "index_extraction_runs_on_source_product_id_and_created_at"
    t.index ["source_product_id"], name: "index_extraction_runs_on_source_product_id"
    t.index ["status"], name: "index_extraction_runs_on_status", where: "(status = 0)"
  end

  create_table "fx_rate_snapshots", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.string "currency_pair", null: false
    t.decimal "rate", precision: 12, scale: 4, null: false
    t.string "source_api", null: false
    t.datetime "updated_at", null: false
    t.index ["currency_pair", "captured_at"], name: "index_fx_rate_snapshots_on_currency_pair_and_captured_at", unique: true
  end

  create_table "invoices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "amount_krw", null: false
    t.datetime "created_at", null: false
    t.datetime "issued_at"
    t.datetime "paid_at"
    t.string "pg_transaction_id"
    t.integer "status", default: 0, null: false
    t.uuid "subscription_id", null: false
    t.datetime "updated_at", null: false
    t.index ["pg_transaction_id"], name: "index_invoices_on_pg_transaction_id", unique: true
    t.index ["subscription_id", "status"], name: "index_invoices_on_subscription_id_and_status"
    t.index ["subscription_id"], name: "index_invoices_on_subscription_id"
  end

  create_table "kc_cert_rules", force: :cascade do |t|
    t.boolean "cert_required", default: true, null: false
    t.string "cert_type"
    t.datetime "created_at", null: false
    t.jsonb "exemption_conditions", default: {}, null: false
    t.string "product_category", null: false
    t.string "reference_law"
    t.datetime "updated_at", null: false
    t.index ["product_category"], name: "index_kc_cert_rules_on_product_category", unique: true
  end

  create_table "listing_variants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_variant_id"
    t.uuid "marketplace_listing_id", null: false
    t.string "option_name", null: false
    t.string "option_value", null: false
    t.bigint "price_krw", null: false
    t.string "sku"
    t.integer "stock_quantity", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["marketplace_listing_id", "external_variant_id"], name: "idx_listing_variants_external_id", unique: true, where: "(external_variant_id IS NOT NULL)"
    t.index ["marketplace_listing_id", "sku"], name: "index_listing_variants_on_marketplace_listing_id_and_sku", unique: true, where: "(sku IS NOT NULL)"
    t.index ["marketplace_listing_id"], name: "index_listing_variants_on_marketplace_listing_id"
  end

  create_table "marketplace_accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "credentials_ciphertext"
    t.integer "provider", null: false
    t.jsonb "rate_limit_config", default: {}, null: false
    t.string "shop_name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "provider"], name: "index_marketplace_accounts_on_account_id_and_provider"
    t.index ["account_id", "shop_name"], name: "index_marketplace_accounts_on_account_id_and_shop_name", unique: true
    t.index ["account_id"], name: "index_marketplace_accounts_on_account_id"
  end

  create_table "marketplace_listings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "catalog_product_id", null: false
    t.datetime "created_at", null: false
    t.string "external_listing_id"
    t.datetime "last_synced_at"
    t.datetime "listed_at"
    t.bigint "listed_price_krw", null: false
    t.uuid "marketplace_account_id", null: false
    t.jsonb "marketplace_attributes", default: {}, null: false
    t.string "marketplace_category_code"
    t.integer "status", default: 0, null: false
    t.jsonb "sync_errors", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_product_id", "marketplace_account_id"], name: "idx_marketplace_listings_uniqueness", unique: true
    t.index ["catalog_product_id"], name: "index_marketplace_listings_on_catalog_product_id"
    t.index ["marketplace_account_id", "external_listing_id"], name: "idx_on_marketplace_account_id_external_listing_id_7451b3de9d", unique: true
    t.index ["marketplace_account_id", "status"], name: "idx_on_marketplace_account_id_status_947aafe36f"
    t.index ["marketplace_account_id"], name: "index_marketplace_listings_on_marketplace_account_id"
  end

  create_table "memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.integer "role", default: 2, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id", "role"], name: "index_memberships_on_account_id_and_role"
    t.index ["account_id"], name: "index_memberships_on_account_id"
    t.index ["user_id", "account_id"], name: "index_memberships_on_user_id_and_account_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "oauth_identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "access_token_ciphertext"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.integer "provider", null: false
    t.text "refresh_token_ciphertext"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["provider", "uid"], name: "index_oauth_identities_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_oauth_identities_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_oauth_identities_on_user_id"
  end

  create_table "order_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "catalog_product_id"
    t.datetime "created_at", null: false
    t.string "external_item_id"
    t.integer "item_status", default: 0, null: false
    t.uuid "marketplace_listing_id"
    t.uuid "order_id", null: false
    t.string "product_name_snapshot", null: false
    t.integer "quantity", null: false
    t.bigint "unit_price_krw", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_product_id"], name: "index_order_items_on_catalog_product_id"
    t.index ["marketplace_listing_id"], name: "index_order_items_on_marketplace_listing_id"
    t.index ["order_id", "external_item_id"], name: "index_order_items_on_order_id_and_external_item_id", unique: true, where: "(external_item_id IS NOT NULL)"
    t.index ["order_id", "item_status"], name: "index_order_items_on_order_id_and_item_status"
    t.index ["order_id"], name: "index_order_items_on_order_id"
  end

  create_table "orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.text "buyer_address_ciphertext"
    t.text "buyer_contact_ciphertext"
    t.text "buyer_name_ciphertext"
    t.datetime "created_at", null: false
    t.string "external_order_id", null: false
    t.uuid "marketplace_account_id", null: false
    t.integer "marketplace_platform", null: false
    t.integer "order_status", default: 0, null: false
    t.datetime "ordered_at", null: false
    t.text "shipping_memo"
    t.bigint "total_amount_krw", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "marketplace_account_id", "external_order_id"], name: "idx_orders_account_external_id", unique: true
    t.index ["account_id", "order_status"], name: "index_orders_on_account_id_and_order_status"
    t.index ["account_id", "ordered_at"], name: "idx_orders_account_active_window", where: "(order_status = ANY (ARRAY[0, 1, 2]))"
    t.index ["account_id", "ordered_at"], name: "index_orders_on_account_id_and_ordered_at"
    t.index ["account_id"], name: "index_orders_on_account_id"
    t.index ["marketplace_account_id"], name: "index_orders_on_marketplace_account_id"
  end

  create_table "return_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "order_id", null: false
    t.string "reason_code", null: false
    t.text "reason_detail"
    t.bigint "refund_amount_krw"
    t.datetime "requested_at", null: false
    t.datetime "resolved_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_return_requests_on_order_id", unique: true
    t.index ["status"], name: "index_return_requests_on_status"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.inet "ip_address"
    t.string "purpose"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_sessions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shipments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.uuid "order_id", null: false
    t.datetime "shipped_at"
    t.bigint "shipping_cost_krw", default: 0, null: false
    t.integer "shipping_provider", null: false
    t.integer "shipping_status", default: 0, null: false
    t.string "tracking_number"
    t.datetime "updated_at", null: false
    t.index ["order_id", "shipping_status"], name: "index_shipments_on_order_id_and_shipping_status"
    t.index ["order_id"], name: "index_shipments_on_order_id"
    t.index ["tracking_number"], name: "index_shipments_on_tracking_number"
  end

  create_table "source_products", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "collected_at"
    t.datetime "created_at", null: false
    t.jsonb "images"
    t.string "original_currency", default: "CNY", null: false
    t.text "original_description"
    t.jsonb "original_images", default: [], null: false
    t.bigint "original_price_cents", null: false
    t.string "original_title", null: false
    t.jsonb "raw_data", default: {}, null: false
    t.string "shop_name"
    t.string "source_id", null: false
    t.integer "source_platform", null: false
    t.string "source_url", null: false
    t.jsonb "specifications"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.jsonb "variants_data"
    t.index "to_tsvector('simple'::regconfig, (COALESCE(original_title, ''::character varying))::text)", name: "index_source_products_on_original_title_tsv", using: :gin
    t.index ["account_id", "source_platform", "source_id"], name: "idx_source_products_account_source_uid", unique: true
    t.index ["account_id", "status"], name: "index_source_products_on_account_id_and_status"
    t.index ["account_id"], name: "index_source_products_on_account_id"
    t.index ["source_url"], name: "index_source_products_on_source_url"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.datetime "current_period_start"
    t.string "external_subscription_id"
    t.string "payment_provider"
    t.integer "plan", null: false
    t.integer "status", default: 0, null: false
    t.datetime "trial_ends_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "external_subscription_id"], name: "index_subscriptions_on_account_id_and_external_subscription_id", unique: true
    t.index ["account_id", "status"], name: "index_subscriptions_on_account_id_and_status"
    t.index ["account_id"], name: "index_subscriptions_on_account_id"
  end

  create_table "support_tickets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.uuid "order_id"
    t.integer "priority"
    t.string "source"
    t.integer "status"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.uuid "user_id"
  end

  create_table "tracking_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "location"
    t.datetime "occurred_at", null: false
    t.uuid "shipment_id", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["shipment_id", "occurred_at"], name: "index_tracking_events_on_shipment_id_and_occurred_at"
    t.index ["shipment_id"], name: "index_tracking_events_on_shipment_id"
  end

  create_table "translation_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.uuid "extraction_run_id", null: false
    t.string "input_hash", null: false
    t.text "input_text", null: false
    t.text "output_text"
    t.integer "provider", null: false
    t.string "source_lang", null: false
    t.integer "status", default: 0, null: false
    t.string "target_lang", null: false
    t.datetime "updated_at", null: false
    t.index ["extraction_run_id", "created_at"], name: "index_translation_runs_on_extraction_run_id_and_created_at"
    t.index ["extraction_run_id"], name: "index_translation_runs_on_extraction_run_id"
    t.index ["provider", "input_hash"], name: "index_translation_runs_on_provider_and_input_hash"
    t.index ["status"], name: "index_translation_runs_on_status", where: "(status = 0)"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "api_token_digest"
    t.datetime "api_token_expires_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "last_sign_in_at"
    t.inet "last_sign_in_ip"
    t.string "name", null: false
    t.string "otp_secret"
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "role"], name: "index_users_on_account_id_and_role"
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "webhook_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_type", null: false
    t.string "external_event_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.integer "provider", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "idx_webhook_events_pending", where: "(processed_at IS NULL)"
    t.index ["account_id", "provider", "external_event_id"], name: "idx_webhook_events_idempotency", unique: true
    t.index ["account_id", "status"], name: "index_webhook_events_on_account_id_and_status"
    t.index ["account_id"], name: "index_webhook_events_on_account_id"
  end

  add_foreign_key "accounts", "users", column: "owner_id"
  add_foreign_key "api_credentials", "accounts"
  add_foreign_key "api_credentials", "users"
  add_foreign_key "audit_logs", "accounts"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "catalog_products", "accounts"
  add_foreign_key "catalog_products", "source_products"
  add_foreign_key "category_mappings", "accounts"
  add_foreign_key "extraction_runs", "source_products"
  add_foreign_key "invoices", "subscriptions"
  add_foreign_key "listing_variants", "marketplace_listings"
  add_foreign_key "marketplace_accounts", "accounts"
  add_foreign_key "marketplace_listings", "catalog_products"
  add_foreign_key "marketplace_listings", "marketplace_accounts"
  add_foreign_key "memberships", "accounts"
  add_foreign_key "memberships", "users"
  add_foreign_key "oauth_identities", "users"
  add_foreign_key "order_items", "catalog_products"
  add_foreign_key "order_items", "marketplace_listings"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "accounts"
  add_foreign_key "orders", "marketplace_accounts"
  add_foreign_key "return_requests", "orders"
  add_foreign_key "sessions", "users"
  add_foreign_key "shipments", "orders"
  add_foreign_key "source_products", "accounts"
  add_foreign_key "subscriptions", "accounts"
  add_foreign_key "support_tickets", "accounts", on_delete: :nullify
  add_foreign_key "support_tickets", "orders", on_delete: :nullify
  add_foreign_key "support_tickets", "users", on_delete: :nullify
  add_foreign_key "tracking_events", "shipments"
  add_foreign_key "translation_runs", "extraction_runs"
  add_foreign_key "users", "accounts"
  add_foreign_key "webhook_events", "accounts"
end
