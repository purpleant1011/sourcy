# Phase 5: Chrome Extension API 엔드포인트 구현

## 완료 사항

### 1. Chrome Extension Auth Controller (`/app/controllers/api/v1/chrome_extension_auth_controller.rb`)

**주요 기능:**
- OAuth2 PKCE Authorization Endpoint (`POST /api/v1/auth/authorize`)
- OAuth2 Token Endpoint (`POST /api/v1/auth/token`)
  - Authorization Code Flow
  - Refresh Token Flow (with token rotation)
- OAuth2 Revoke Endpoint (`DELETE /api/v1/auth/revoke`)
- Authentication Status Check (`GET /api/v1/auth/status`)

**보안 특징:**
- PKCE (Proof Key for Code Exchange) - CSRF 방지
- Code Verifier/Challenge 검증
- Token Rotation - Refresh Token 교체
- JWT Encoding (HS256)
- Session 기반 인증

### 2. Chrome Extension Products Controller (`/app/controllers/api/v1/chrome_extension_products_controller.rb`)

**주요 기능:**
- Product Extraction (`POST /api/v1/products/extract`)
  - 상품 데이터 검증
  - 중복 상품 확인 및 업데이트
  - 플랫폼 매핑 (Taobao, AliExpress, Amazon, etc.)
  - 가격 변환 (cents 단위)
  - 이미지, 변형, 사양 저장
- Product List (`GET /api/v1/source_products`)
  - Cursor-based pagination
  - 필터링 (status, platform)
- Product Details (`GET /api/v1/source_products/:id`)
  - 상세 정보 포함 (description, variants, specifications)
- Product Statistics (`GET /api/v1/products/stats`)
  - 전체, 대기 중, 준비됨, 실패, 발행됨
  - 플랫폼별 분석
- Product Update (`PUT /api/v1/source_products/:id`)
- Product Delete (`DELETE /api/v1/source_products/:id`)

**데이터 매핑:**
```ruby
# Platform String → Enum
'taobao' → :taobao
'tmall' → :tmall
'aliexpress' → :aliexpress
'amazon' → :amazon
'amazon_jp' → :amazon
'1688' → :taobao
```

### 3. Chrome Extension User Controller (`/app/controllers/api/v1/chrome_extension_user_controller.rb`)

**주요 기능:**
- User Info (`GET /api/v1/user`)
  - 사용자 정보
  - 계정 정보
  - 구독 정보
  - 사용량 통계
  - API Key (마스킹)
- User Update (`PUT /api/v1/user`)
  - 이름 변경
  - 비밀번호 변경
- Account Update (`PUT /api/v1/user/account`)
  - 계정 이름 변경
  - 비즈니스 유형 변경

### 4. Auth Controller (`/app/controllers/auth_controller.rb`)

**주요 기능:**
- Chrome Extension OAuth2 Authorization Page (`GET /auth/chrome_extension`)
- Authorization Approval (`POST /auth/chrome_extension/approve`)
  - Authorization Code 생성
  - PKCE 검증 준비
  - Chrome Extension Callback URL로 리다이렉트
- Authorization Denial (`POST /auth/chrome_extension/deny`)
  - 세션 정리
  - 에러 전달

### 5. Views

**OAuth2 Authorization Page** (`/app/views/auth/chrome_extension_authorize.html.erb` - 368 라인)
- Extension 정보 표시
- 권한 요청 목록
- 사용자 정보 확인
- 권한 부여/거부 버튼
- 보안 공지
- 반응형 디자인 (Tailwind CSS 스타일)

**OAuth2 Error Page** (`/app/views/auth/chrome_extension_error.html.erb` - 234 라인)
- 에러 메시지 표시
- 에러 발생 이유 설명
- 대시보드/닫기 버튼
- 지원 센터 링크

### 6. Routes (`/config/routes.rb`)

**OAuth2 Routes:**
```ruby
get "auth/chrome_extension", to: "auth#chrome_extension", as: :chrome_extension_auth
post "auth/chrome_extension/approve", to: "auth#chrome_extension_approve", as: :chrome_extension_approve
post "auth/chrome_extension/deny", to: "auth#chrome_extension_deny", as: :chrome_extension_deny
```

**API v1 Routes:**
```ruby
namespace :api do
  namespace :v1 do
    # Chrome Extension OAuth2 (PKCE)
    post "auth/authorize", to: "chrome_extension_auth#authorize"
    post "auth/token", to: "chrome_extension_auth#token"
    delete "auth/revoke", to: "chrome_extension_auth#revoke"
    get "auth/status", to: "chrome_extension_auth#status"

    # Chrome Extension User
    get "user", to: "chrome_extension_user#show"
    put "user", to: "chrome_extension_user#update"
    put "user/account", to: "chrome_extension_user#update_account"

    # Chrome Extension Products
    post "products/extract", to: "chrome_extension_products#extract"
    get "products/stats", to: "chrome_extension_products#stats"
    resources :source_products, only: %i[index show update destroy], controller: "chrome_extension_products"
  end
end
```

## API Endpoints

### Authentication

#### 1. OAuth2 Authorization Code Flow

**Step 1: Start OAuth2 Flow**
```
POST /api/v1/auth/authorize
Content-Type: application/json

{
  "client_id": "sourcy-chrome-extension",
  "code_challenge": "BASE64URL_ENCODED(SHA256(code_verifier))",
  "code_challenge_method": "S256",
  "redirect_uri": "https://sourcy.com/oauth/callback",
  "state": "random_state_string"
}

Response:
{
  "success": true,
  "data": {
    "authorization_url": "https://app.sourcy.com/auth/chrome_extension?session_id=..."
  }
}
```

**Step 2: User Approves Authorization**

사용자는 authorization_url로 이동하여 로그인하고 권한을 부여합니다.

**Step 3: Exchange Code for Tokens**
```
POST /api/v1/auth/token
Content-Type: application/json

{
  "grant_type": "authorization_code",
  "code": "authorization_code_from_step_2",
  "code_verifier": "original_code_verifier",
  "redirect_uri": "https://sourcy.com/oauth/callback",
  "client_id": "sourcy-chrome-extension"
}

Response:
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "BAhJIj...Z2ViIgpjcmVhdGVkX2F0Ij...",
    "expires_in": 86400,
    "expires_at": 1640995200,
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "name": "John Doe",
      "role": "admin",
      "account_id": "uuid"
    }
  }
}
```

#### 2. Refresh Token Flow

```
POST /api/v1/auth/token
Content-Type: application/json

{
  "grant_type": "refresh_token",
  "refresh_token": "previous_refresh_token",
  "client_id": "sourcy-chrome-extension"
}

Response:
{
  "success": true,
  "data": {
    "access_token": "new_access_token",
    "refresh_token": "new_refresh_token",  # Rotated!
    "expires_in": 86400,
    "expires_at": 1641081600,
    "user": { ... }
  }
}
```

#### 3. Revoke Token

```
DELETE /api/v1/auth/revoke
Content-Type: application/json

{
  "token": "access_or_refresh_token"
}

Response:
{
  "success": true,
  "data": {
    "revoked": true
  }
}
```

#### 4. Check Authentication Status

```
GET /api/v1/auth/status
Authorization: Bearer <access_token>

Response:
{
  "success": true,
  "data": {
    "authenticated": true,
    "expires_at": 1640995200
  }
}
```

### User

#### Get User Info

```
GET /api/v1/user
Authorization: Bearer <access_token>

Response:
{
  "success": true,
  "data": {
    "id": "uuid",
    "email": "user@example.com",
    "name": "John Doe",
    "role": "admin",
    "account_id": "uuid",
    "account_name": "My Store",
    "business_type": "individual",
    "status": "active",
    "created_at": "2022-01-01T00:00:00.000Z",
    "subscription": {
      "plan": "Pro",
      "status": "active",
      "expires_at": "2022-02-01T00:00:00.000Z"
    },
    "usage": {
      "products_count": 100,
      "listed_count": 50,
      "this_month_imports": 10
    },
    "api_key": "sk_e...xyz"
  }
}
```

### Products

#### Extract Product

```
POST /api/v1/products/extract
Authorization: Bearer <access_token>
Idempotency-Key: <unique_key>
Content-Type: application/json

{
  "platform": "taobao",
  "source_id": "123456789",
  "title": "Product Title",
  "price": 99.99,
  "currency": "CNY",
  "url": "https://item.taobao.com/item.htm?id=123456789",
  "description": "Product description",
  "shop_name": "Shop Name",
  "images": ["url1", "url2", "url3"],
  "variants": [
    {
      "name": "Color",
      "values": ["Red", "Blue", "Green"]
    }
  ],
  "specifications": {
    "Weight": "1.5kg",
    "Dimensions": "10x20x30cm"
  },
  "collected_at": "2022-01-01T00:00:00.000Z"
}

Response (201 Created):
{
  "success": true,
  "data": {
    "id": "uuid",
    "platform": "taobao",
    "source_id": "123456789",
    "title": "Product Title",
    "price": 99.99,
    "currency": "CNY",
    "url": "https://item.taobao.com/item.htm?id=123456789",
    "shop_name": "Shop Name",
    "images": ["url1"],
    "status": "pending",
    "collected_at": "2022-01-01T00:00:00.000Z",
    "created_at": "2022-01-01T00:00:00.000Z"
  }
}
```

#### Get Product Statistics

```
GET /api/v1/products/stats
Authorization: Bearer <access_token>

Response:
{
  "success": true,
  "data": {
    "total": 100,
    "pending": 10,
    "ready": 80,
    "failed": 5,
    "listed": 50,
    "by_platform": {
      "taobao": 40,
      "aliexpress": 30,
      "amazon": 30
    }
  }
}
```

#### List Products

```
GET /api/v1/source_products
Authorization: Bearer <access_token>

Response:
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "platform": "taobao",
      "source_id": "123456789",
      "title": "Product Title",
      "price": 99.99,
      "currency": "CNY",
      "status": "ready",
      "collected_at": "2022-01-01T00:00:00.000Z"
    },
    ...
  ],
  "meta": {
    "page": 1,
    "per_page": 25,
    "total": null,
    "next_cursor": "eyJpZCI6InV1aWQiLCJvcmRlcl92YWx1ZSI6IjIwMjItMDEtMDFUMDA6MDA6MDAuMDAwWiJ9"
  }
}
```

## 보안 특징

### 1. OAuth2 PKCE
- CSRF 방지를 위해 code_verifier와 code_challenge 사용
- S256 SHA-256 해싱
- State parameter for CSRF protection

### 2. JWT Token Management
- Access Token: 24시간 만료
- Refresh Token: 30일 만료
- HS256 Algorithm
- Token Rotation (Refresh token 교체)

### 3. Idempotency
- 모든 mutation 요청에 Idempotency-Key 헤더 필수
- 중복 요청 방지

### 4. Rate Limiting
- X-RateLimit-Limit 헤더
- X-RateLimit-Remaining 헤더
- X-RateLimit-Reset 헤더

### 5. Account Scoping
- 모든 데이터 요청은 Current.account로 스코핑
- NO default_scope

## 테스트 방법

### 1. OAuth2 Flow 테스트

```bash
# Step 1: Start OAuth2 flow
curl -X POST http://localhost:3000/api/v1/auth/authorize \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "sourcy-chrome-extension",
    "code_challenge": "your_code_challenge",
    "code_challenge_method": "S256",
    "redirect_uri": "https://sourcy.com/oauth/callback",
    "state": "random_state"
  }'

# Step 2: User approves (open returned URL in browser)

# Step 3: Exchange code for tokens
curl -X POST http://localhost:3000/api/v1/auth/token \
  -H "Content-Type: application/json" \
  -d '{
    "grant_type": "authorization_code",
    "code": "authorization_code",
    "code_verifier": "your_code_verifier",
    "redirect_uri": "https://sourcy.com/oauth/callback",
    "client_id": "sourcy-chrome-extension"
  }'
```

### 2. Product Extraction 테스트

```bash
# Extract product
curl -X POST http://localhost:3000/api/v1/products/extract \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: unique-key-123" \
  -d '{
    "platform": "taobao",
    "source_id": "123456789",
    "title": "Test Product",
    "price": 99.99,
    "currency": "CNY",
    "url": "https://item.taobao.com/item.htm?id=123456789"
  }'

# Get product stats
curl -X GET http://localhost:3000/api/v1/products/stats \
  -H "Authorization: Bearer <access_token>"
```

## 다음 단계

Phase 5가 완료되었습니다. 다음 단계:

1. API 테스트 작성 (RSpec)
2. 통합 테스트 (Chrome Extension + API)
3. 배포 준비 (Production 환경 설정)
