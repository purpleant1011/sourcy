# Sourcy 배포 체크리스트

## 📋 사전 준비

### 1. 환경 변수 설정
- [ ] `.env.production` 파일 생성 (`.env.example` 기준)
- [ ] 환경 변수 확인:
  - [ ] `DATABASE_URL` - PostgreSQL 연결 정보
  - [ ] `REDIS_URL` - Redis 연결 정보 (캐시/세션/Job 큐)
  - [ ] `SECRET_KEY_BASE` - Rails secret key base
  - [ ] `RAILS_ENV=production`
  - [ ] `RAILS_LOG_LEVEL=info`
  - [ ] `RAILS_SERVE_STATIC_FILES=true` (CDN 미사용 시)
  - [ ] `ALLOWED_HOSTS` - 허용된 호스트 목록
  - [ ] `ADMIN_USERNAME` - 관리자 기본 인증 ID
  - [ ] `ADMIN_PASSWORD` - 관리자 기본 인증 비밀번호

### 2. Credentials 설정
```bash
bin/rails credentials:edit --environment=production
```

필요한 항목:
- [ ] `secret_key_base` - 암호화 키
- [ ] `jwt_secret` - JWT 토큰 암호화 키
- [ ] `smtp` - 이메일 SMTP 설정
  - [ ] `address`
  - [ ] `port`
  - [ ] `domain`
  - [ ] `user_name`
  - [ ] `password`
  - [ ] `authentication`
- [ ] `active_record_encryption` - DB 암호화 키
  - [ ] `primary_key`
  - [ ] `deterministic_key`
  - [ ] `key_derivation_salt`
- [ ] `admin` - 관리자 인증 정보 (Credential 우선)
  - [ ] `username`
  - [ ] `password`
- [ ] `portone` - PortOne 결제 연동 설정
- [ ] `google_translate_api_key` - Google Translate API 키

### 3. 데이터베이스 준비
- [ ] PostgreSQL 데이터베이스 생성
- [ ] `RAILS_ENV=production bundle exec rails db:create`
- [ ] `RAILS_ENV=production bundle exec rails db:migrate`
- [ ] `RAILS_ENV=production bundle exec rails db:seed` (필요 시)
- [ ] 데이터베이스 백업 설정 (주기적 자동화)
- [ ] 슬롯 스케일링 설정 (연결 풀 크기)

### 4. SSL 인증서
- [ ] SSL 인증서 발급 (Let's Encrypt / 기타 CA)
- [ ] 역방향 프록시(Nginx/HAProxy) SSL 설정
- [ ] `config.force_ssl = true` 활성화 확인 (production.rb)
- [ ] HSTS 헤더 설정

### 5. 스토리지 설정
- [ ] Active Storage 설정 (로컬 vs S3)
- [ ] S3 사용 시:
  - [ ] `config/storage.yml`에 S3 설정
  - [ ] AWS Credentials 설정
  - [ ] 버킷 생성 및 접근 권한 설정
  - [ ] CDN(CloudFront) 연결 (선택)
- [ ] 로컬 사용 시:
  - [ ] `config.active_storage.service = :local` 확인
  - [ ] 공유 스토리지 마운트 (K8s/Cloud)
  - [ ] 정기 백업 설정

## 🚀 배포 절차

### 1. 코드 배포
- [ ] Git에서 최신 코드 가져오기
- [ ] `bundle install --deployment --without development test`
- [ ] `RAILS_ENV=production bundle exec rails assets:precompile`
- [ ] `RAILS_ENV=production bundle exec rails db:migrate`
- [ ] 프로세스 재시작

### 2. 서비스 시작
```bash
# Procfile 기반 (Heroku/Foreman)
heroku scale web=1 worker=1 cable=1

# 또는 Systemd (VPS)
sudo systemctl start sourcy-web
sudo systemctl start sourcy-worker
sudo systemctl start sourcy-cable
```

- [ ] Web 서버(Puma) 시작
- [ ] Worker(Solid Queue) 시작
- [ ] Cable(Solid Cable) 시작

### 3. 헬스 체크
- [ ] `GET /up` 엔드포인트 확인 (200 OK)
- [ ] 웹사이트 접속 확인
- [ ] 로그인 테스트
- [ ] API 엔드포인트 테스트
- [ ] 웹훅 엔드포인트 외부 접근 테스트

### 4. 로그 확인
- [ ] Web 서버 로그 확인 (`logs/production.log`)
- [ ] Worker 로그 확인 (`log/solid_queue.log`)
- [ ] Cable 로그 확인
- [ ] 에러/예외 확인 (Sentry/Rollbar 연동 시)

## 🔧 모니터링 & 알림

### 1. 로그 수집
- [ ] 로그 애그리게이터 설정 (Papertrail/LogDNA/CloudWatch)
- [ ] 로그 레벨 확인 (`info` 이상)

### 2. 에러 추적
- [ ] Sentry/Rollbar/ Honeybadger 설정
- [ ] 알림 채널 설정 (Slack/Email)
- [ ] 에러 레벨 필터링

### 3. 성능 모니터링
- [ ] APM 도구 설정 (New Relic/DataDog/Skylight)
- [ ] 데이터베이스 쿼리 모니터링
- [ ] N+1 쿼리 감지
- [ ] 메모리/CPU 사용량 모니터링

### 4. Uptime 모니터링
- [ ] Uptime robot/Pingdom 설정
- [ ] 응답 시간 모니터링
- [ ] 장애 알림 설정

## 🛡️ 보안

### 1. 네트워크 보안
- [ ] 방화벽 규칙 설정 (SSH 포트 제한)
- [ ] DDOS 보호 (Cloudflare/Railgun)
- [ ] WAF 설정 (AWS WAF/Cloudflare WAF)
- [ ] Rate Limiting 확인 (`Rack::Attack` 설정)

### 2. 애플리케이션 보안
- [ ] `config.hosts` 허용 호스트 설정
- [ ] CSRF 보호 활성화
- [ ] Content Security Policy 설정
- [ ] HTTP 보안 헤더 확인
  - [ ] `X-Frame-Options`
  - [ ] `X-Content-Type-Options`
  - [ ] `X-XSS-Protection`
  - [ ] `Strict-Transport-Security`

### 3. 데이터 보안
- [ ] DB 암호화 키 안전 보관
- [ ] PII 필드 암호화 확인 (`ActiveRecord Encryption`)
- [ ] API 토큰 암호화 확인
- [ ] 백업 암호화

### 4. 권한 관리
- [ ] 데이터베이스 사용자 최소 권한
- [ ] 파일 시스템 권한 확인
- [ ] Secret 관리 도구 사용 (Vault/AWS Secrets Manager)

## 📊 백업 & 복구

### 1. 데이터베이스 백업
- [ ] 자동 백업 설정 (일일)
- [ ] 백업 저장 위치 (S3/내부 스토리지)
- [ ] 백업 보관 기간 (최소 30일)
- [ ] 지리적 중복 (다른 리전에 복제)

### 2. 파일 백업
- [ ] Active Storage 업로드 백업
- [ ] 로그 파일 밑업 (선택)

### 3. 복구 테스트
- [ ] 매월 백업 복구 테스트 수행
- [ ] 복구 절차 문서화
- [ ] RTO(복구 시간 목표) / RPO(데이터 손실 허용) 설정

## 🔄 CI/CD

### 1. 테스트 자동화
- [ ] PR 시 테스트 자동 실행
- [ ] `bundle exec rspec` 통과 확인
- [ ] `bundle exec rubocop` 통과 확인
- [ ] 보안 스캔 (Brakeman)

### 2. 배포 자동화
- [ ] Main 브랜치 머지 시 자동 배포
- [ ] 블루-그린 배포 (무중단)
- [ ] 롤백 절차

### 3. 스테이징 환경
- [ ] 스테이징 환경 구성
- [ ] 운영 트래픽 미러링 (선택)
- [ ] 배포 전 스테이징 테스트

## 📝 문서화

- [ ] 배포 절차 문서화
- [ ] 장애 대응 절차 (Runbook)
- [ ] 온콜 연락처
- [ ] 아키텍처 다이어그램

## ✅ 배포 후 검증

### 1. 기능 테스트
- [ ] 사용자 회원가입/로그인
- [ ] 제품 등록/수정/삭제
- [ ] 마켓플레이스 연동
- [ ] 주문 처리 흐름
- [ ] 결제 테스트 (Sandbox)

### 2. 성능 테스트
- [ ] 부하 테스트 (k6/Artillery)
- [ ] 동시 사용자 테스트
- [ ] 응답 시간 확인 (< 200ms P50, < 500ms P95)

### 3. 보안 테스트
- [ ] OWASP ZAP 스캔
- [ ] 취약점 스캔 (Snyk/Dependabot)
- [ ] 침투 테스트 (주기적)

## 🎯 최종 점검

- [ ] 모든 헬스 체크 통과
- [ ] 로그에 에러 없음
- [ ] 모든 서비스 정상 작동
- [ ] 모니터링/알림 설정 완료
- [ ] 백업 설정 완료
- [ ] 보안 설정 완료
- [ ] 문서화 완료

---

**배포 완료! 🎉**

**참고:**
- 배포 전 반드시 스테이징 환경에서 테스트
- 배포 시에는 항상 백업 후 진행
- 장애 발생 시 Runbook 참조하여 즉시 대응
