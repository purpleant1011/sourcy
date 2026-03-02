# Sourcy Chrome Extension

크로스보더 이커머스 자동화를 위한 Chrome Extension입니다. 중국 이커머스(Taobao, AliExpress, 1688, Amazon)에서 제품을 수집하여 한국 마켓플레이스(Naver SmartStore, Coupang, Gmarket, 11st)에 발행할 수 있습니다.

## Features

- 🌍 **다중 플랫폼 지원**: Taobao, Tmall, AliExpress, 1688, Amazon
- 🔐 **OAuth2 PKCE 인증**: 보안 안전한 인증 플로우
- 🔄 **JWT 토큰 관리**: 자동 토큰 리프레시 및 로테이션
- 📦 **상품 추출**: DOM 기반 실시간 상품 데이터 추출
- 💾 **로컬 캐싱**: Chrome Storage API를 활용한 데이터 저장
- 🎨 **모던 UI**: Turbo, Tailwind CSS 기반 반응형 인터페이스
- ⚡ **최신 기술**: Chrome Extension Manifest V3, ES6+, Async/Await

## Installation

### Development Mode

1. Chrome 브라우저에서 `chrome://extensions`로 이동
2. "Developer mode"를 활성화
3. "Load unpacked" 클릭
4. `chrome-extension` 디렉토리 선택

### Production Mode

Chrome Web Store에 업로드 후 설치
## Icon Generation

Chrome Extension에 필요한 아이콘 파일(16x16, 32x32, 48x48, 128x128)을 생성하는 방법:

### 방법 1: Figma 사용 (추천)
1. Figma에서 아이콘 디자인 (128x128)
2. Export 하여 각 사이즈로 리사이징
3. `icons/` 디렉토리에 저장

### 방법 2: Online Tools
- [Favicon.io](https://favicon.io/): SVG를 PNG로 변환
- [Canva](https://www.canva.com/): 템플릿 사용
- [Photopea](https://www.photopea.com/): 온라인 Photoshop

### 방법 3: Command Line (ImageMagick)
```bash
# ImageMagick 설치 후
brew install imagemagick  # macOS

# icon.svg이 있는 경우
convert icon.svg -resize 16x16 icons/icon16.png
convert icon.svg -resize 32x32 icons/icon32.png
convert icon.svg -resize 48x48 icons/icon48.png
convert icon.svg -resize 128x128 icons/icon128.png
```

### 방법 4: Placeholder 아이콘 (개발용)
다양한 온라인 도구로 아이콘을 생성하거나, 다운로드 가능한 무료 아이콘 라이브러리를 사용하세요.

**권장 형식:**
- 파일 형식: PNG (배경 투명)
- 색상 모드: RGB
- 압축: 없음

**디자인 가이드라인:**
- 단순하고 인식 가능한 디자인
- 브랜드 색상 사용 (파란색: #3B82F6)
- 다운로드/상품 추출 관련 아이콘


## Architecture

```
chrome-extension/
├── manifest.json          # Manifest V3 설정
├── background/
│   └── background.js      # Service Worker (JWT, OAuth2, API 통신)
├── content/
│   ├── content.js         # Content Script (상품 추출, DOM 조작)
│   └── content.css         # Content 스타일
├── popup/
│   ├── popup.html         # Popup UI
│   ├── popup.css          # Popup 스타일
│   └── popup.js           # Popup 로직
├── settings/
│   ├── settings.html      # 설정 페이지 (settings.html)
│   ├── settings.css       # 설정 페이지 스타일 (settings.css)
│   └── settings.js        # 설정 페이지 로직 (settings.js)
└── icons/
    ├── icon16.png
    ├── icon32.png
    ├── icon48.png
    └── icon128.png
```

## Components

### 1. Background Service Worker (`background.js`)

**주요 기능:**
- JWT 토큰 관리 (저장, 리프레시, 로테이션)
- OAuth2 PKCE 플로우 처리
- API 호출 중계 (인증 헤더 추가)
- 메시지 라우팅 (popup ↔ content script ↔ background)
- Chrome Storage 관리
- 주기적 토큰 리프레시 스케줄링

**OAuth2 PKCE 플로우:**
1. Code Verifier/Challenge 생성
2. Authorization URL 구성
3. Authorization 페이지 열기
4. Callback 처리 (code → token)
5. Access/Refresh Token 저장
6. 주기적 토큰 리프레시

### 2. Content Script (`content.js`)

**주요 기능:**
- 플랫폼 감지 (URL 기반)
- 상품 데이터 추출 (DOM 기반)
- Extract Button 표시
- Background Script와 통신
- 사용자 알림 표시

**지원 플랫폼:**
- **Taobao/Tmall**: 제품 ID, 제목, 가격, 이미지, 상세정보, 샵명
- **AliExpress**: 제품 ID, 제목, 가격, 이미지, 상세정보, 샵명
- **Amazon**: ASIN, 제목, 가격, 이미지, 상세정보, 셀러명
- **1688**: Taobao와 유사한 구조

### 3. Popup (`popup.html/js/css`)

**주요 기능:**
- 로그인/로그아웃 UI
- 사용자 정보 표시
- 상품 통계 (총 수, 대기 중, 발행됨)
- 최근 상품 목록
- 빠른 액션 (현재 페이지 추출, 대시보드 열기)

**상태:**
- Loading
- Not Logged In
- Logged In
- Error

### 4. Settings (`settings.html/js/css`)

**주요 기능:**
- 계정 정보 관리
- 일반 설정 (Auto Extract, 알림, 사운드)
- 플랫폼 활성화/비활성화
- 데이터 & 프라이버시 (캐시 삭제, 데이터 내보내기, 데이터 삭제)
- 지원 링크 (Help, Documentation, Feedback)
- 버전 정보

## API Integration

### Base URL
```
https://app.sourcy.com/api/v1
```

### Endpoints

#### Authentication
- `POST /auth/authorize` - OAuth2 Authorization
- `POST /auth/token` - Token Exchange / Refresh
- `POST /auth/revoke` - Token Revoke

#### Products
- `POST /products/extract` - Extract Product
- `GET /products` - List Products (with pagination)
- `GET /products/stats` - Product Statistics

#### User
- `GET /user` - User Information

### Request Format

```javascript
// API 호출 예시
async function apiCall(endpoint, options = {}) {
  const url = `${API_BASE_URL}${endpoint}`;
  
  const response = await fetch(url, {
    ...options,
    headers: {
      ...options.headers,
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`,
      'Idempotency-Key': generateIdempotencyKey() // Mutation 요청에 필수
    }
  });
  
  return await response.json();
}
```

### Response Format

```json
{
  "success": true,
  "data": { ... }
}
```

## Product Data Structure

### Extracted Product (from content.js)
```javascript
{
  "platform": "taobao", // or "aliexpress", "amazon", "tmall"
  "source_id": "123456789", // Product ID / ASIN
  "title": "Product Title",
  "price": 99.99,
  "currency": "CNY", // or "USD", "JPY"
  "images": ["url1", "url2", ...],
  "description": "Product description",
  "shop_name": "Shop Name",
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
  "url": "https://...",
  "collectedAt": "2024-01-01T00:00:00.000Z"
}
```

## Security

### JWT Token Management
- **Access Token**: 24시간 만료
- **Refresh Token**: 자동 로테이션
- **Storage**: Chrome Storage Local (암호화된 상태)
- **Refresh Schedule**: 만료 5분 전 자동 리프레시

### OAuth2 PKCE Flow
- **Proof Key for Code Exchange**: CSRF 방지
- **Code Verifier**: 랜덤 32바이트
- **Code Challenge**: SHA-256 해시
- **State**: CSRF 방지용 랜덤 토큰

### Best Practices
1. 민감한 데이터는 Background Service Worker에서만 처리
2. Content Script는 DOM 조작만 담당
3. Token은 Storage에만 저장, 메모리에 노출 최소화
4. HTTPS 통신만 허용
5. Content Security Policy (CSP) 준수

## Browser Compatibility

- Chrome 88+ (Manifest V3 지원)
- Edge 88+
- Brave 88+

## Development

### Requirements
- Node.js 16+
- Chrome 88+

### Setup
```bash
cd chrome-extension
# No build process needed - plain JavaScript/CSS
```

### Testing
1. Chrome에서 `chrome://extensions`로 이동
2. Developer mode 활성화
3. "Load unpacked"로 디렉토리 로드
4. 각 플랫폼에서 테스트:
   - Taobao: https://item.taobao.com/item.htm?id=123456789
   - AliExpress: https://www.aliexpress.com/item/123456789.html
   - Amazon: https://www.amazon.com/dp/B0XXXXXXX

### Debugging
1. Background Script: `chrome://extensions` → Service Worker → Inspect
2. Content Script: F12 → Console
3. Popup: Popup 열고 F12 → Console

### Logging
```javascript
console.log('[Sourcy Extension] Message:', data);
```

## Deployment

### Chrome Web Store
1. 패키징된 ZIP 업로드
2. Privacy Policy URL 제공
3. 스크린샷 제공
4. 리뷰 및 승인 대기

### Version Management
```json
{
  "version": "1.0.0",
  "version_name": "1.0.0"
}
```

## Troubleshooting

### Common Issues

**1. Authentication fails**
- Background Script Console 확인
- OAuth2 callback URL 확인
- API 상태 확인

**2. Product extraction not working**
- Content Script Console 확인
- DOM 구조 변경 확인 (플랫폼 업데이트)
- Permissions 확인

**3. Token refresh fails**
- 네트워크 상태 확인
- API 가용성 확인
- Storage 확인

## License

MIT

## Support

- Help Center: https://docs.sourcy.com/help
- Documentation: https://docs.sourcy.com
- Feedback: https://sourcy.com/feedback
- Email: support@sourcy.com
