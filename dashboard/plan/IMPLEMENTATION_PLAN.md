# Migration Dashboard — 단계별 구현 계획

## 원칙

- 각 단계는 **독립적으로 실행·확인 가능**해야 한다
- 단계가 완료될 때마다 `docker-compose up`으로 동작 확인
- 이전 단계가 완료된 것을 전제로 다음 단계를 시작한다
- 각 단계의 산출물은 명확하게 정의한다

---

## Phase 0: 프로젝트 뼈대 (기반 구조)

> 목표: 전체 디렉토리 구조, Docker Compose, 환경변수 템플릿 완성

### 산출물
```
dashboard/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── config/
│   └── settings.yaml
├── db/                         # (gitignore)
├── backend/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py                 # FastAPI app 뼈대 (라우터 미포함)
│   └── core/
│       ├── db.py               # SQLite + WAL + 테이블 생성
│       └── env_loader.py       # Pydantic BaseSettings
└── frontend/
    ├── Dockerfile
    ├── package.json
    ├── vite.config.ts
    ├── tailwind.config.ts
    ├── tsconfig.json
    └── nginx.conf
```

### 완료 기준
- `docker-compose up` → backend `http://localhost:8000/health` 200 OK
- `docker-compose up` → frontend `http://localhost:3000` Vite 기본 화면
- SQLite 파일 자동 생성 + 8개 테이블 스키마 확인
- `.env.example`의 모든 키가 `env.sh` 변수와 1:1 매핑

---

## Phase 1: Backend API 핵심 + 인증

> 목표: JWT 인증, Config Registry, 헬스체크 API 완성

### 산출물
```
backend/
├── api/
│   ├── auth.py                 # JWT 로그인/토큰 발급, 사용자 관리
│   ├── config.py               # Config Registry CRUD + /healthcheck
│   └── events.py               # Event Log CRUD (기본)
├── models/
│   ├── config_entry.py
│   └── event.py
└── core/
    └── scheduler.py            # APScheduler 뼈대 (job 없음)
```

### 완료 기준
- `POST /api/auth/login` → JWT 토큰 반환
- `GET /api/config` → Config Registry 항목 목록
- `POST /api/config/healthcheck` → Source DB / Target DB / GG 연결 상태 JSON
- `GET /api/events` → 빈 이벤트 목록 (페이지네이션)
- `/docs` Swagger UI에서 모든 엔드포인트 확인

---

## Phase 2: Frontend 기반 + Overview 화면

> 목표: React 앱 구조, 전역 레이아웃, Overview 화면 완성

### 산출물
```
frontend/src/
├── main.tsx
├── App.tsx                     # 라우터 (react-router-dom)
├── components/
│   ├── layout/
│   │   ├── GlobalHeader.tsx    # Phase 인디케이터, GG 신호등, 알림 배지
│   │   └── Sidebar.tsx         # 11개 화면 네비게이션
│   └── ui/                     # shadcn/ui 컴포넌트
├── pages/
│   └── Overview.tsx            # Phase 타임라인, DB 연결 상태, Validation 진행률
├── hooks/
│   └── useApi.ts               # axios 인스턴스 + JWT 헤더 자동 주입
└── store/
    └── authStore.ts            # Zustand 인증 상태
```

### 완료 기준
- 로그인 화면 → JWT 토큰 획득 → 전역 헤더 표시
- Overview 화면: Phase 0~8 타임라인 렌더링 (mock 데이터)
- 전역 헤더: Go/No-Go 배지, Phase 인디케이터, GG 신호등 (mock)
- Sidebar 11개 메뉴 클릭 시 각 페이지로 라우팅 (빈 페이지)

---

## Phase 3: GG Monitor + LAG 이력 수집

> 목표: GG LAG 실시간 모니터링 화면 + APScheduler LAG 수집

### 산출물
```
backend/api/
└── goldengate.py               # GG REST API v2 프록시 + LAG 조회

backend/core/
└── gg_client.py                # httpx.AsyncClient (TLS, Basic Auth)
└── scheduler.py                # LAG 수집 job (5분 간격)

frontend/src/pages/
└── GGMonitor.tsx               # LAG 24h 차트, 프로세스 카드, 제어 버튼

frontend/src/components/
└── LagChart.tsx                # Recharts 24h 슬라이딩 윈도우 + 30s 임계선
```

### 완료 기준
- APScheduler 5분마다 `lag_history` 테이블에 LAG 기록
- `GET /api/gg/status` → EXT1/PUMP1/REP1 상태 JSON
- `GET /api/gg/lag-history?hours=24` → lag_history 레코드
- GGMonitor 화면: LAG 차트 렌더링, 프로세스 신호등, START/STOP 버튼

---

## Phase 4: Runbook Viewer + DB Status

> 목표: 런북 MD 렌더링 + Step 진행 마킹, Oracle DB 상태 비교

### 산출물
```
backend/api/
├── runbook.py                  # plan/*.md 읽기, Step 상태 CRUD, SQL 블록 추출
└── database.py                 # python-oracledb Thin 쿼리 (파라미터 비교, 세션, 스키마 diff)

backend/core/
└── oracle_client.py            # oracledb 연결 풀 (Thin 모드)

backend/models/
└── script_run.py               # step_progress 모델

frontend/src/pages/
├── RunbookViewer.tsx            # MD 렌더링, Step 마킹, WARNING 패널
└── DBStatus.tsx                 # Source/Target 비교, Schema Diff 패널
```

### 완료 기준
- `GET /api/runbook/files` → plan/*.md 목록
- `GET /api/runbook/{file}/steps` → Step 목록 + 완료 상태
- `POST /api/runbook/{file}/steps/{step_id}/complete` → Step 완료 처리
- RunbookViewer: markdown 렌더링 + SQL 코드블록 copy 버튼 + Step 완료 마킹
- `GET /api/db/compare` → NLS_CHARACTERSET 등 파라미터 비교 JSON
- DBStatus: Source/Target 파라미터 테이블, 차이 빨간 강조

---

## Phase 5: Script Runner (WebSocket)

> 목표: 화이트리스트 기반 스크립트 실행 + WebSocket 로그 스트리밍

### 산출물
```
backend/api/
└── scripts.py                  # 화이트리스트 + subprocess + WebSocket + PID 관리

frontend/src/pages/
└── ScriptRunner.tsx             # 스크립트 카드, 실행 UI, 실시간 로그

frontend/src/components/
└── LogStreamer.tsx              # WebSocket 로그 스트리밍 뷰어
```

### 완료 기준
- `GET /api/scripts` → 화이트리스트 스크립트 목록 (Phase 필터, 역할 필터)
- `WS /api/scripts/{id}/run` → 실행 로그 실시간 스트리밍
- `POST /api/scripts/{id}/kill` → 실행 중 스크립트 강제 종료
- HIGH 이상 스크립트: 사유 입력 폼 강제
- CRITICAL 스크립트: `X-Confirm-Token` 헤더 검증
- 동시 실행 방지: 실행 중 스크립트 잠금 표시

---

## Phase 6: Validation (136항목) + Go/No-Go

> 목표: xlsx → SQLite seed, 136항목 UI, Go/No-Go 배지 연동

### 산출물
```
backend/api/
└── validation.py               # 136항목 CRUD + xlsx seed + Go/No-Go 집계

backend/models/
└── validation.py

frontend/src/pages/
└── Validation.tsx               # 4레벨 드릴다운 UI, 도메인 진행 바

frontend/src/components/
└── GoNoBadge.tsx               # 전역 헤더 + Validation 상단 배지
```

### 완료 기준
- 서버 기동 시 `docs/00.validation_plan.xlsx` → SQLite 자동 import (136항목)
- `GET /api/validation/summary` → PASS/WARN/FAIL 집계 + Go/No-Go 판정
- Validation 화면: 도메인별 진행 바 + 드릴다운 + 항목 메모/담당자 수정
- 전역 헤더 Go/No-Go 배지 실시간 반영

---

## Phase 7: Cut-over Console + 롤백

> 목표: Cut-over 타이머, 10단계 체크리스트, 롤백 콘솔

### 산출물
```
frontend/src/pages/
├── CutoverConsole.tsx           # 타이머, GG LAG 인라인, 단계 체크리스트
└── RollbackConsole.tsx          # 롤백 체크리스트 + RDS 유지 카운트다운
```

### 완료 기준
- Cut-over 시작 조건: 24h LAG 달성 + HIGH 항목 전체 PASS → 버튼 활성화
- 시작 후: 초 단위 카운트업, 20분 경고(노란), 25분 위험(빨간+알림음)
- step10_cutover_execute.sh 기반 10단계 체크리스트 렌더링
- 롤백 버튼 → 롤백 콘솔 진입 → 사유 입력 + 시각 기록

---

## Phase 8: Event Log + Execution History + Config

> 목표: 타임라인 이벤트 뷰어, 실행 이력, Config Registry UI

### 산출물
```
frontend/src/pages/
├── EventLog.tsx                 # 세로 타임라인 + PDF/CSV 내보내기
├── ExecutionHistory.tsx         # 이력 목록 + 과거 로그 재조회
└── ConfigRegistry.tsx           # 공통 파라미터 관리 UI
```

### 완료 기준
- EventLog: 당일 전체 이벤트 타임라인, PDF 내보내기 (jsPDF)
- ExecutionHistory: 과거 실행 이력 클릭 → 로그 파일 재조회
- ConfigRegistry: 값 편집 + 잠금 + 변경자/시각 기록

---

## Phase 9: Settings + 알림 체계 + D-Day 모드

> 목표: 알림 체계 완성, D-Day 4분할 모드, 모바일 최적화

### 산출물
```
backend/api/
└── alerts.py                   # 알림 CRUD + APScheduler 감시 job

backend/core/
└── scheduler.py                # 헬스체크(30초), LAG 감시(5분) job 완성

frontend/src/pages/
└── Settings.tsx                 # 임계값 설정, 사용자 관리, 헬스체크

frontend/src/components/
├── AlertBanner.tsx              # Critical 팝업 + 알림음
└── DDayLayout.tsx              # 4분할 레이아웃 + 팝아웃 지원
```

### 완료 기준
- Critical 알림: 화면 팝업 + 알림음 + 확인 강제
- GG ABEND 감지 → 즉시 Critical 알림
- D-Day 모드 토글: Overview → 4분할 레이아웃
- 팝아웃: 각 패널 `window.open()`으로 독립 창 분리
- Settings: 사용자 역할 관리, LAG 임계값 조정

---

## 단계별 의존성 요약

```
Phase 0 (뼈대)
  └→ Phase 1 (Backend API)
       └→ Phase 2 (Frontend 기반)
            ├→ Phase 3 (GG Monitor)     ← Phase 1 필요
            ├→ Phase 4 (Runbook+DB)     ← Phase 1 필요
            ├→ Phase 5 (Script Runner)  ← Phase 1 필요
            ├→ Phase 6 (Validation)     ← Phase 1 필요
            └→ Phase 7 (Cut-over)       ← Phase 3, 6 완료 권장
                 └→ Phase 8 (Log/History/Config)
                      └→ Phase 9 (알림+D-Day)
```

Phase 2 완료 후 Phase 3~6은 **병렬 진행 가능** (API/화면이 독립적).

---

## 각 Phase 예상 작업량

| Phase | 주요 작업 | 파일 수 |
|-------|-----------|--------|
| 0 | Docker, 뼈대, SQLite 스키마 | ~15 |
| 1 | FastAPI 라우터 4개, JWT, 모델 | ~12 |
| 2 | React 앱, 레이아웃, Overview | ~15 |
| 3 | GG API, APScheduler, LAG 차트 | ~8 |
| 4 | Runbook MD, Oracle 연결, DB 비교 | ~10 |
| 5 | Script 화이트리스트, WebSocket | ~8 |
| 6 | xlsx seed, Validation CRUD, UI | ~8 |
| 7 | Cut-over 타이머, 롤백 콘솔 | ~6 |
| 8 | Event Log, History, Config UI | ~8 |
| 9 | 알림, D-Day 모드, Settings | ~10 |

---

## 다음 세션 시작 방법

각 세션 시작 시:
1. 이 문서로 현재 Phase 확인
2. 해당 Phase의 "완료 기준" 항목을 checklist로 삼아 진행
3. 완료 후 완료 기준 항목 체크 + 다음 Phase 안내
