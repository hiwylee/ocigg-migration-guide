# Migration Dashboard

AWS RDS Oracle SE → OCI DBCS Oracle SE 마이그레이션 운영 대시보드.

GoldenGate 모니터링, 런북 실행, 136항목 검증, Cut-over 진행을 하나의 화면에서 관리한다.

---

## 구성

```
dashboard/
├── backend/        FastAPI (Python 3.11) — REST API + WebSocket + APScheduler
├── frontend/       React 18 + Vite + Tailwind CSS — SPA
├── db/             SQLite WAL (런타임 생성, git 제외)
├── .env.example    환경변수 템플릿
├── podman-compose.yml
└── plan/
    └── IMPLEMENTATION_PLAN.md   단계별 구현 계획
```

**포트**

| 서비스 | 포트 | 설명 |
|--------|------|------|
| Frontend (nginx) | 3000 | 웹 UI |
| Backend (uvicorn) | 8000 | REST API · Swagger |

Frontend의 `/api/` 요청은 nginx가 backend:8000 으로 프록시한다. 브라우저는 포트 3000만 사용하면 된다.

---

## 빠른 시작

### 1. 환경변수 설정

```bash
cp .env.example .env
vi .env          # 아래 필수 항목 채우기
```

**필수 수정 항목**

| 변수 | 설명 | 예시 |
|------|------|------|
| `JWT_SECRET_KEY` | 랜덤 비밀키 (반드시 변경) | `openssl rand -hex 32` 값 |
| `ADMIN_PASSWORD` | 초기 관리자 비밀번호 | `MySecurePass!` |
| `SRC_DB_HOST` | AWS RDS 엔드포인트 | `mydb.xxxx.ap-northeast-1.rds.amazonaws.com` |
| `SRC_DBA_USER` / `SRC_DBA_PASS` | 소스 DBA 계정 | |
| `TGT_DB_HOST` | OCI DBCS IP 또는 FQDN | |
| `TGT_DBA_USER` / `TGT_DBA_PASS` | 타겟 DBA 계정 | |
| `GG_ADMIN_URL` | OCI GoldenGate Admin Server URL | `https://gg.example.com` |
| `GG_ADMIN_USER` / `GG_ADMIN_PASS` | GG Admin 계정 | |

**선택 항목**

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `GG_CA_BUNDLE` | `/app/certs/ca-bundle.crt` | GG TLS CA 번들 경로 |
| `LAG_WARNING_SECONDS` | `15` | LAG 경고 임계값(초) |
| `LAG_CRITICAL_SECONDS` | `30` | LAG 위험 임계값(초) |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `480` | JWT 만료(분) |
| `CORS_ORIGIN` | `http://localhost:3000` | CORS 허용 Origin |

### 2. 기동

```bash
# db 디렉토리 생성 (최초 1회)
mkdir -p db

# 빌드 + 기동
podman-compose up -d --build

# 로그 확인
podman-compose logs -f
```

### 3. 접속

```
http://localhost:3000
계정: admin / (ADMIN_PASSWORD에 설정한 값)
```

### 4. 정지

```bash
podman-compose down
```

---

## 화면 구성 (11개)

| 경로 | 화면 | 주요 기능 |
|------|------|-----------|
| `/` | Overview | Phase 타임라인, DB 연결 상태, Validation 진행률 |
| `/gg-monitor` | GG Monitor | LAG 24h 차트, EXT/PUMP/REP 신호등, START/STOP |
| `/runbook` | Runbook Viewer | plan/*.md 렌더링, Step 완료 마킹, SQL 복사 |
| `/db-status` | DB Status | 소스/타겟 파라미터 비교, Schema Diff |
| `/script-runner` | Script Runner | 화이트리스트 스크립트 실행, WebSocket 로그 스트리밍 |
| `/validation` | Validation | 136항목 드릴다운, Go/No-Go 배지 |
| `/cutover` | Cut-over Console | 시작 조건 확인, 10단계 체크리스트, 카운트업 타이머 |
| `/event-log` | Event Log | 날짜별 타임라인, PDF 내보내기 |
| `/execution-history` | Execution History | 스크립트 실행 이력, 과거 로그 재조회 |
| `/config` | Config Registry | 공통 파라미터 인라인 편집 / 잠금 |
| `/settings` | Settings | 사용자 관리, LAG 임계값 조정 |

---

## 주요 기능 상세

### GG Monitor
- APScheduler가 5분 간격으로 LAG을 수집해 `lag_history` 테이블에 저장
- 헬스체크가 30초 간격으로 ABEND를 감지 → Critical 알림 자동 생성
- LAG이 30초 초과 시 전역 헤더 신호등이 빨간색으로 전환

### Script Runner
- `backend/api/scripts.py`의 화이트리스트에 등록된 스크립트만 실행 가능
- HIGH 이상: 실행 사유 입력 강제
- CRITICAL: `X-Confirm-Token` 헤더 검증
- WebSocket으로 실행 로그 실시간 스트리밍
- 동시 실행 방지 (같은 스크립트 중복 실행 잠금)

### Validation
- 서버 기동 시 `docs/00.validation_plan.xlsx` → SQLite 자동 import (136항목)
- PASS / WARN / FAIL / PENDING 상태 직접 업데이트 가능
- **Go/No-Go 판정 기준**:
  - `GO`: HIGH 항목 FAIL 0건 + WARN 0건
  - `CONDITIONAL_GO`: HIGH 항목 FAIL 0건 + WARN 1건 이상
  - `NO_GO`: HIGH 항목 FAIL 1건 이상
  - `PENDING`: 미완료 항목 존재

### Cut-over Console
- **시작 조건**: Validation FAIL 0건 + GG REP LAG ≤ 30초 (동시 만족 시 버튼 활성화)
- 타이머: 시작 후 초 단위 카운트업 → 20분 황색 경고 → 25분 적색 + 알림음
- 10단계 체크리스트 완료 체크/취소 기능
- 롤백 버튼 → `/rollback` (사유 입력 + 14일 RDS 유지 카운트다운)

### 알림 체계 (AlertBanner)
- 15초마다 미확인 CRITICAL 알림을 폴링
- Critical 알림 존재 시 화면 전체 팝업 + 비프음 3회
- 확인(Acknowledge) 버튼을 눌러야만 팝업이 닫힘
- 헤더의 Bell 아이콘에 미확인 알림 수 표시

### D-Day 모드
- 헤더의 **D-Day** 버튼 클릭 → 4분할 전체화면
- 4개 패널: Overview / GG Monitor / Validation / Cut-over Console
- 각 패널 우상단 아이콘 클릭 → `window.open()`으로 독립 팝아웃 창 분리

### Config Registry
- `config_registry` 테이블의 키/값 인라인 편집 (클릭 → Enter 저장 / Esc 취소)
- 잠금(Lock) 후에는 UI에서 편집 불가 (해제는 admin이 DB 직접 처리)
- 변경자/변경 시각 자동 기록

---

## 사용자 역할 (Role)

| 역할 | 권한 |
|------|------|
| `admin` | 전체 권한 + 사용자 관리 |
| `migration_leader` | Cut-over 시작/롤백, Config 잠금 |
| `src_dba` | 소스 DB 관련 스크립트 실행 |
| `tgt_dba` | 타겟 DB 관련 스크립트 실행 |
| `gg_operator` | GoldenGate 관련 스크립트 실행 |
| `viewer` | 읽기 전용 (실행/편집 불가) |

사용자 추가/역할 변경은 Settings → 사용자 관리 탭 (admin 권한 필요).

---

## GG TLS 인증서 설정

OCI GoldenGate가 자체 서명 인증서를 사용하는 경우:

```bash
# CA 인증서를 certs/ 디렉토리에 배치
cp your-ca.crt dashboard/backend/certs/ca-bundle.crt

# .env에서 경로 확인 (컨테이너 내부 경로)
GG_CA_BUNDLE=/app/certs/ca-bundle.crt
```

Dockerfile에서 `COPY . .` 로 `certs/` 디렉토리가 이미지에 포함된다. 인증서 교체 시 `podman-compose build --no-cache backend` 후 재기동.

---

## 스크립트 화이트리스트 관리

실행 가능한 스크립트는 `backend/api/scripts.py`의 `SCRIPT_METADATA` 딕셔너리에 등록한다.

```python
SCRIPT_METADATA = {
    "01_pre_migration/step04_network_test.sh": {
        "phase": 0,
        "risk": "LOW",       # LOW / MEDIUM / HIGH / CRITICAL
        "role": "src_dba",   # 실행 가능 역할
    },
    ...
}
```

새 스크립트 추가 후 `podman-compose build --no-cache backend && podman-compose up -d`.

---

## 운영 참고

### 로그 확인

```bash
# 전체 로그
podman-compose logs -f

# backend만
podman logs -f dashboard_backend_1

# 스크립트 실행 로그 (컨테이너 내부)
podman exec dashboard_backend_1 ls /app/scripts/logs/
```

### DB 직접 접근

```bash
# SQLite 쉘 (호스트에서)
sqlite3 dashboard/db/dashboard.db

# 유용한 쿼리
SELECT * FROM alerts WHERE confirmed_at IS NULL;
SELECT * FROM phase_progress;
SELECT key, value FROM config_registry WHERE key IN ('CURRENT_PHASE','CUTOVER_STARTED_AT');
```

### Config 잠금 해제 (DB 직접)

```bash
sqlite3 dashboard/db/dashboard.db \
  "UPDATE config_registry SET locked=0 WHERE key='CUTOVER_STARTED_AT';"
```

### 이미지 재빌드

```bash
# 코드 변경 후 전체 재빌드
podman-compose build --no-cache
podman-compose up -d --force-recreate
```

---

## API 문서

백엔드 기동 후 접속:

```
http://localhost:8000/docs    # Swagger UI
http://localhost:8000/redoc   # ReDoc
```

주요 엔드포인트:

| 메서드 | 경로 | 설명 |
|--------|------|------|
| `POST` | `/api/auth/login` | 로그인 (form-data: username, password) |
| `GET` | `/api/validation/summary` | Go/No-Go 집계 |
| `GET` | `/api/gg/status` | GoldenGate 프로세스 상태 |
| `GET` | `/api/gg/lag-history` | LAG 이력 (hours 파라미터) |
| `GET` | `/api/cutover/status` | Cut-over 진행 상태 |
| `POST` | `/api/cutover/start` | Cut-over 시작 |
| `POST` | `/api/cutover/rollback` | 롤백 시작 |
| `GET` | `/api/alerts` | 알림 목록 |
| `GET` | `/api/scripts/runs` | 스크립트 실행 이력 전체 |
| `WS` | `/api/scripts/{id}/run` | 스크립트 실행 (WebSocket) |
