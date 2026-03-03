# frozen_string_literal: true
# 테스트용 Seed 데이터

puts "Seeding database..."

# 1. Account 생성
account = Account.find_or_create_by!(slug: "test-account") do |a|
  a.name = "테스트 셀러"
  a.plan = :free
  a.settings = {
    "default_margin_percent" => 30,
    "auto_translate" => true,
    "auto_kc_check" => true,
    "timezone" => "Asia/Seoul"
  }
end
puts "Account: #{account.name}"

# 2. User (Admin) 생성
user = User.find_or_initialize_by(email: "admin@sourcy.kr")
unless user.persisted?
  user.assign_attributes(
    account: account,
    name: "관리자",
    password: "password123!",
    password_confirmation: "password123!",
    role: :owner
  )
  user.save!
  account.update!(owner: user)
end
puts "User: #{user.email} / password: password123!"

# 3. Subscription 생성
Subscription.find_or_create_by!(account: account) do |s|
  s.plan = :free
  s.status = :active
  s.current_period_start = Time.current
  s.current_period_end = 1.month.from_now
end
puts "Subscription: free plan"

# 4. MarketplaceAccount 생성
marketplace = MarketplaceAccount.find_or_initialize_by(account: account, shop_name: "테스트 스마트스토어")
unless marketplace.persisted?
  marketplace.assign_attributes(
    provider: :naver_smartstore,
    credentials_ciphertext: { client_id: "test_id", client_secret: "test_secret" }.to_json,
    status: :active
  )
  marketplace.save!
end
puts "MarketplaceAccount: #{marketplace.shop_name}"

# 5. SourceProduct 샘플 생성
3.times do |i|
  SourceProduct.find_or_create_by!(
    account: account,
    source_platform: :aliexpress,
    source_id: "ALI-#{1000 + i}"
  ) do |sp|
    sp.source_url = "https://www.aliexpress.com/item/#{1000 + i}.html"
    sp.original_title = ["귀여운 고양이 인형 30cm", "LED 야간등 USB 충전식", "스테인리스 텀블러 500ml"][i]
    sp.original_description = "고품질 상품입니다."
    sp.original_price_cents = [1500, 800, 1200][i] * 100
    sp.original_currency = "CNY"
    sp.original_images = []
    sp.raw_data = {}
    sp.status = :ready
    sp.collected_at = Time.current
  end
end
puts "SourceProducts: 3 samples"

# 6. CatalogProduct 샘플 생성
SourceProduct.where(account: account).each_with_index do |sp, i|
  next if CatalogProduct.exists?(source_product: sp)
  CatalogProduct.create!(
    account: account,
    source_product: sp,
    translated_title: ["귀여운 고양이 인형 30cm 봉제인형", "USB LED 야간등 무드램프", "스테인리스 보온 텀블러 500ml"][i],
    translated_description: "국내 판매용 상품 설명입니다.",
    base_price_krw: [29800, 15800, 22000][i],
    cost_price_krw: [8000, 4000, 7000][i],
    fx_rate_snapshot: 188.5,
    margin_percent: 30.0,
    status: :draft,
    kc_cert_required: false,
    kc_cert_status: :unknown,
    risk_flags: {}
  )
end
puts "CatalogProducts: #{CatalogProduct.where(account: account).count} products"

# 7. KC 인증 규칙 샘플
[
  { product_category: "전기용품", cert_required: true, cert_type: "KC", reference_law: "전기용품 및 생활용품 안전관리법" },
  { product_category: "완구", cert_required: true, cert_type: "KC", reference_law: "어린이제품 안전 특별법" },
  { product_category: "의류", cert_required: false, cert_type: nil, reference_law: nil }
].each do |rule|
  KcCertRule.find_or_create_by!(product_category: rule[:product_category]) do |r|
    r.cert_required = rule[:cert_required]
    r.cert_type = rule[:cert_type]
    r.reference_law = rule[:reference_law]
    r.exemption_conditions = {}
  end
end
puts "KcCertRules: #{KcCertRule.count} rules"

# 8. BrandFilter 샘플
[
  { brand_name: "Nike", keyword: "나이키", action: :warn },
  { brand_name: "Apple", keyword: "애플", action: :warn },
  { brand_name: "LV", keyword: "루이비통", action: :block }
].each do |filter|
  BrandFilter.find_or_create_by!(keyword: filter[:keyword]) do |bf|
    bf.brand_name = filter[:brand_name]
    bf.action = filter[:action]
  end
end
puts "BrandFilters: #{BrandFilter.count} filters"

puts "\n✅ Seed complete!"
puts "=" * 50
puts "접속 정보:"
puts "  웹 로그인: http://localhost:3000/session/new"
puts "  이메일: admin@sourcy.kr"
puts "  비밀번호: password123!"
puts "  관리자: http://localhost:3000/admin"
puts "  관리자 ID: test_admin / PW: test_password"
puts "=" * 50
