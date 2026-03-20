# OCI GoldenGate Migration Guide

> AWS RDS (Oracle SE) → OCI DBCS (Oracle SE) 온라인 마이그레이션 런북 & 자동화 스크립트

[![Oracle SE](https://img.shields.io/badge/Oracle-SE-red)](https://www.oracle.com/)
[![OCI GoldenGate](https://img.shields.io/badge/OCI-GoldenGate-orange)](https://www.oracle.com/integration/goldengate/)
[![AWS RDS](https://img.shields.io/badge/AWS-RDS-yellow)](https://aws.amazon.com/rds/)

---

## 개요

이 저장소는 **AWS RDS Oracle SE**에서 **OCI DBCS Oracle SE**로의 온라인 마이그레이션을 위한
운영 절차서(Runbook), 검증 프레임워크, 실행 스크립트를 포함합니다.

| 항목 | 내용 |
|------|------|
| 소스 | AWS RDS Oracle SE (ap-northeast-1) |
| 타겟 | OCI DBCS Oracle SE (ap-tokyo-1) |
| 복제 도구 | OCI GoldenGate Cloud (Managed) |
| 초기 적재 | Oracle Data Pump (expdp / impdp) |
| 서비스 중단 목표 | Cut-over 시 30분 이내 |
| 검증 항목 | 136개 (5개 도메인) |

### 마이그레이션 아키텍처

```
[AWS RDS Oracle SE]
    │
    ├─── ① expdp (FLASHBACK_SCN 고정, DATA_ONLY)
    │         └──→ [OCI Object Storage] ──→ impdp ──→ [OCI DBCS Oracle SE]
    │
    └─── ② OCI GoldenGate Extract
              └──→ Data Pump ──→ Replicat ──→ [OCI DBCS Oracle SE]
                                               (SCN 이후 델타 지속 적용)
```

---

## 저장소 구조

```
crscube/
├── README.md                          # 이 문서
│
├── docs/
│   └── 00.validation_plan.xlsx        # 검증 체크리스트 136항목 (6시트)
│
├── plan/                              # 운영 절차서 (Runbook)
│   ├── migration_plan.md              # 마스터 플랜: 8단계 전략, 롤백, 기준
│   ├── migration_plan_draft.md        # 작업용 초안
│   ├── 00.pre_req_rds_se_db.md        # ★ 소스 DB 사전 요건 (RDS SE)
│   ├── 00.pre_req_rds_se_db.docx      # 소스 DB 사전 요건 (Word 버전)
│   ├── 01.pre_migration.md            # Phase 0~2 런북: 환경/소스/타겟 DB 준비
│   ├── 02.migration.md                # Phase 3~5 런북: GG 구성, 초기 적재, 델타 동기화
│   └── 03.validation.md               # Phase 6~7 런북: 검증, Cut-over, 안정화
│
└── scripts/                           # 실행 스크립트
    ├── README.md                      # 스크립트 사용 가이드
    ├── config/
    │   └── env.sh                     # ★ 환경변수 설정 (실행 전 필수)
    ├── 01_pre_migration/              # Phase 0~2 스크립트 (24개)
    ├── 02_migration/                  # Phase 3~5 스크립트 (18개)
    └── 03_validation/                 # Phase 6~8 스크립트 (12개)
```

---

## 8단계 마이그레이션 플랜

| Phase | 이름 | 타이밍 | 주요 산출물 |
|-------|------|--------|------------|
| 0 | 사전 준비 & 환경 점검 | D-14 ~ D-10 | 인벤토리, 인프라 구성 |
| 1 | 소스 DB 준비 (AWS RDS) | D-10 ~ D-7 | GG 파라미터, Supplemental Log |
| 2 | 타겟 DB 준비 (OCI DBCS) | D-10 ~ D-7 | DDL 이전, 특수 객체 준비 |
| 3 | OCI GoldenGate 구성 | D-7 ~ D-5 | Extract / Pump / Replicat |
| 4 | 초기 데이터 적재 | D-5 ~ D-2 | expdp → impdp 완료 |
| 5 | 델타 동기화 | D-2 ~ D-Day | GG LAG < 30초 안정화 24h+ |
| 6 | 검증 (136항목) | D-1 ~ D-Day | Go/No-Go 판정 |
| 7 | Cut-over | D-Day | 소스 차단 → 전환 완료 (30분 이내) |
| 8 | 안정화 | D+1 ~ D+14 | 모니터링, 롤백 창 유지 |

---

## 문서 사용 가이드

### 어떤 문서부터 읽어야 하나?

```
처음 접하는 경우
└─→ migration_plan.md            전체 전략 및 아키텍처 파악

소스 DB 담당자 (AWS RDS DBA)
└─→ 00.pre_req_rds_se_db.md     ★ 소스 DB 사전 설정 항목만 모은 문서
    └─→ 01.pre_migration.md      STEP 07~14 상세 절차

타겟 DB 담당자 (OCI DBCS DBA)
└─→ 01.pre_migration.md          STEP 15~24 (타겟 DB 준비)

OCI GoldenGate 담당자
└─→ 02.migration.md              Phase 3~5 GG 구성 및 복제

검증 담당자
└─→ 03.validation.md             Phase 6~7 검증 및 Cut-over
    └─→ docs/validation_plan.xlsx 136항목 체크리스트
```

### 소스 DB 사전 설정 요약 (`00.pre_req_rds_se_db.md`)

OCI GoldenGate Extract가 AWS RDS Oracle SE를 소스로 사용하기 위한 **모든 사전 설정**을
단일 문서로 정리한 것입니다. 다음 항목을 다룹니다.

| 섹션 | 내용 |
|------|------|
| RDS SE 제약 사항 | ALTER SYSTEM 불가 명령 및 RDS 우회 방법 |
| 필수 파라미터 | `enable_goldengate_replication`, `streams_pool_size`, archivelog 보존 |
| Supplemental Logging | MIN + PK/UI/FK + PK 없는 테이블 ALL COLUMNS |
| GGADMIN 계정 | 권한 목록, 접속 테스트, 패스워드 만료 관리 |
| 네트워크 | OCI GG Egress IP → RDS 보안그룹 TCP 1521 |
| 인벤토리 | BITMAP Index, XMLTYPE, LOB, 파티션 테이블 현황 |
| 의사결정 항목 | 7가지 팀 간 합의 필요 사항 |
| 완료 체크리스트 | P/S/A/I 카테고리별 확인 항목 |

Word 버전: `plan/00.pre_req_rds_se_db.docx`

---

## 스크립트 빠른 시작

### 1. 환경변수 설정

```bash
cp scripts/config/env.sh scripts/config/env.sh.bak
vi scripts/config/env.sh
```

```bash
# 주요 설정 항목
SRC_DB_HOST="mydb.xxxx.ap-northeast-2.rds.amazonaws.com"
SRC_DB_SID="ORCL"
TGT_DB_HOST="dbcs-node1.subnet.vcn.oraclevcn.com"
TGT_DB_SID="ORCL"
MIGRATION_SCHEMAS="APP1,APP2"
```

> ⚠️ `env.sh`에 비밀번호가 포함됩니다. `.gitignore`에 추가하거나 별도 시크릿 관리 도구를 사용하세요.

### 2. 실행 권한 부여

```bash
find scripts/ -name "*.sh" -exec chmod +x {} \;
```

### 3. Phase별 실행

```bash
# Phase 0~2: 소스 DB 사전 준비 (SQL 스크립트)
sqlplus MIGRATION_USER/password@${SRC_TNS} @scripts/01_pre_migration/step07_enable_gg.sql
sqlplus MIGRATION_USER/password@${SRC_TNS} @scripts/01_pre_migration/step12_supplemental_log.sql

# Phase 0~2: 네트워크 테스트 (Shell 스크립트)
./scripts/01_pre_migration/step04_network_test.sh

# Phase 3~5: GoldenGate 구성
./scripts/02_migration/step04_extract_setup.sh
./scripts/02_migration/step16_start_replication.sh

# Phase 6~8: 검증
sqlplus MIGRATION_USER/password@${SRC_TNS} @scripts/03_validation/step03_data_validation.sql
./scripts/03_validation/step10_cutover_execute.sh
```

> 전체 스크립트 목록 및 실행 환경(소스/타겟/GG) 안내: [`scripts/README.md`](scripts/README.md)

---

## 검증 프레임워크 (136항목)

`docs/00.validation_plan.xlsx` — 6개 시트

| 시트 | 도메인 | 항목 수 | 주요 내용 |
|------|--------|--------|----------|
| 01_GG_Process | GoldenGate 프로세스 | 28 | Extract/Pump/Replicat 사전체크, 모니터링 |
| 02_Static_Schema | 정적 스키마 | 38 | 테이블/인덱스/제약/시퀀스/INVALID 객체 |
| 03_Data_Validation | 데이터 정합성 | 25 | Row Count, Checksum, LOB, NLS, 참조 무결성 |
| 04_Special_Objects | 특수 객체 | 42 | MV, Trigger, DB Link, DBMS_JOB→SCHEDULER, 파티션 |
| 05_Migration_Caution | 마이그레이션 주의 | 26 | SE 제약, GG 제한, DDL 복제 |

**Go/No-Go 기준**

- `HIGH` 우선순위 항목 → 전부 **PASS** 필수
- `WARN` 항목 → 원인 분석 및 완화 방안 기록 후 진행 가능
- `FAIL` (Critical) → **즉시 중단**

---

## 롤백 계획

| 시점 | 롤백 방법 | 소요 시간 |
|------|----------|---------|
| Phase 4 이전 | 소스 RDS 그대로 사용 재개 | 즉시 |
| Cut-over 후 | 소스 RDS → 애플리케이션 재연결 | 30분 이내 |
| Cut-over 후 2주 이내 | 소스 RDS 인스턴스 유지 (롤백 창) | — |

> Cut-over 후 **2주간 소스 RDS를 유지**합니다. 이 기간 내 심각한 문제 발생 시 롤백 가능.

---

## 주요 제약 사항 (Oracle SE + AWS RDS)

| 제약 | 내용 | 대응 |
|------|------|------|
| `ALTER SYSTEM` 불가 | RDS에서 직접 실행 제한 | `rdsadmin_util` API 또는 Parameter Group 사용 |
| Streams Pool 자동 할당 불가 | SE는 AMM 대상 외 | Parameter Group에서 수동 설정 (재기동 필요) |
| BITMAP Index | SE 타겟 미지원 | NORMAL B-Tree Index로 대체 |
| DDL 복제 범위 제한 | TABLE 오브젝트만 자동 복제 | 나머지 DDL은 수동 동기화 절차 수립 |
| XMLTYPE 복제 미지원 | GG 공식 미지원 | GG 복제 제외 후 컷오버 시 수동 동기화 |

---

## 참고 문서

| 문서 | 링크 |
|------|------|
| OCI GoldenGate 공식 문서 | https://docs.oracle.com/en/cloud/paas/goldengate-service/ |
| AWS RDS Oracle 파라미터 가이드 | https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.Oracle.Parameters.html |
| Oracle GoldenGate SE 가이드 | https://docs.oracle.com/en/middleware/goldengate/core/21.3/oracle-db/ |
| OCI DBCS 문서 | https://docs.oracle.com/en-us/iaas/base-database/index.html |
