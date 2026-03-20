# 마이그레이션 단계 절차서 (Migration Runbook)

> **프로젝트**: AWS RDS (Oracle SE) → OCI DBCS (Oracle SE) 온라인 마이그레이션
> **문서 유형**: 운영 절차서 (Runbook / SOP)
> **적용 범위**: Phase 3 (OCI GG 구성) + Phase 4 (초기 데이터 적재) + Phase 5 (델타 동기화)
> **참조 문서**: `plan/migration_plan.md`, `plan/01.pre_migration.md`
> **문서 버전**: v1.0 | 작성일: 2026-03-17

---

## 문서 이력

| 버전 | 날짜 | 변경 내용 | 작성자 |
|------|------|-----------|--------|
| v1.0 | 2026-03-17 | 최초 작성 | |

---

## 담당자 및 역할

| 역할 | 담당 | 연락처 | 주요 책임 |
|------|------|--------|-----------|
| 마이그레이션 리더 | | | 전체 조율, 단계 전환 승인 |
| 소스 DBA (AWS) | | | expdp 실행, GG Extract 모니터링 |
| 타겟 DBA (OCI) | | | impdp 실행, GG Replicat 모니터링 |
| OCI GG 담당자 | | | GG Deployment, Extract/Pump/Replicat 설정 |
| 인프라/네트워크 담당 | | | OCI Object Storage, 방화벽 설정 |

---

## 전제 조건 (본 절차서 실행 전 확인)

> 아래 항목이 모두 완료되어야 본 절차서를 실행할 수 있습니다. (`01.pre_migration.md` 완료 체크리스트 서명 필수)

| # | 항목 | 확인 | 확인자 |
|---|------|------|--------|
| 1 | ENABLE_GOLDENGATE_REPLICATION = TRUE | ☐ | |
| 2 | Supplemental Logging (MIN) 활성화 | ☐ | |
| 3 | PK 없는 테이블 ALL COLUMNS 로깅 적용 완료 | ☐ | |
| 4 | RDS Redo Log 보존 기간 ≥ 48h | ☐ | |
| 5 | Streams Pool ≥ 256MB 설정 | ☐ | |
| 6 | GGADMIN / MIGRATION_USER 계정 생성 및 권한 부여 완료 | ☐ | |
| 7 | 타겟 DBCS NLS 파라미터 소스와 일치 | ☐ | |
| 8 | METADATA_ONLY impdp 완료 — 타겟 스키마 구조 이전 완료 | ☐ | |
| 9 | 오브젝트 완전성 전수 비교 완료 (소스/타겟 COUNT 일치) | ☐ | |
| 10 | 타겟 INVALID 객체 0건 확인 | ☐ | |
| 11 | 소스 통계정보 STATS_EXPORT_TABLE Export 완료 | ☐ | |
| 12 | Trigger DISABLE / FK DISABLE 스크립트 준비 완료 | ☐ | |

---

## 전체 마이그레이션 단계 흐름

```
[Phase 3] OCI GG 구성 (D-7 ~ D-5)
  STEP 01. OCI GG Deployment 확인
  STEP 02. 소스/타겟 Connection 생성 및 연결 테스트
  STEP 03. Heartbeat Table 추가
  STEP 04. Extract (EXT1) 파라미터 설정 및 등록
  STEP 05. Data Pump (PUMP1) 파라미터 설정 및 등록
  STEP 06. Replicat (REP1) 파라미터 설정 및 등록
            ↓
         [Phase 3 완료 체크리스트 확인]
            ↓
[Phase 4] 초기 데이터 적재 (D-5 ~ D-2)
  STEP 07. UNDO / Flashback 사전 확인
  STEP 08. expdp SCN 고정 및 Export SCN 기록
  STEP 09. Extract SCN 기준점 재등록
  STEP 10. DATA_ONLY expdp Export 실행
  STEP 11. Dump 파일 OCI Object Storage 전송
  STEP 12. 타겟 FK/Trigger DISABLE 및 impdp Import 실행
  STEP 13. 통계정보 Import (옵션 A)
  STEP 14. Import 후 오브젝트 상태 확인
  STEP 15. Import 후 초기 Row Count 확인
            ↓
         [Phase 4 완료 체크리스트 확인]
            ↓
[Phase 5] 델타 동기화 (D-2 ~ D-Day)
  STEP 16. GG 복제 시작 (ATCSN)
  STEP 17. GG 프로세스 상태 초기 확인
  STEP 18. LAG 안정화 모니터링 (24h+)
            ↓
         [Phase 5 완료 체크리스트 확인]
            ↓
         [→ 03.validation.md 검증 단계 진행]
```

---

## 표기 규칙

| 기호 | 의미 |
|------|------|
| `[소스]` | AWS RDS에서 실행 |
| `[타겟]` | OCI DBCS에서 실행 |
| `[GG]` | OCI GG Admin Server (GGSCI)에서 실행 |
| `[OCI콘솔]` | OCI 관리 콘솔에서 수행 |
| `[로컬]` | 작업자 PC 또는 배스천 호스트에서 실행 |
| ✅ | 기대 결과와 일치 — 다음 단계 진행 |
| ❌ | 불일치 — 즉시 중단 후 원인 분석 |
| ⚠️ | 허용 범위 내 — 원인 기록 후 진행 |

---

# Phase 3: OCI GoldenGate 구성

---

## STEP 01. OCI GG Deployment 확인

**목적**: OCI GG Deployment가 정상 기동 중이며, Oracle SE 19c를 지원하는 버전인지 확인
**담당**: OCI GG 담당자
**예상 소요**: 20분
**실행 환경**: `[OCI콘솔]`

---

### 1-1. Deployment 상태 및 버전 확인

```
[OCI콘솔] Oracle Database → GoldenGate → Deployments
  - Deployment 상태: Active
  - GoldenGate 버전 확인 (Oracle 19c SE 지원 여부 릴리즈 노트 대조)
  - 자동 업데이트(Auto Upgrade) 정책: 복제 중 자동 패치 비활성화 설정 확인
```

**자동 업데이트 비활성화 확인**:
```
[OCI콘솔] GoldenGate Deployment → Maintenance → Auto Upgrade: Disabled
※ 복제 중 자동 업그레이드 발생 시 Extract/Replicat ABEND 가능 → 반드시 비활성화
```

### 1-2. Admin Server 로그인 테스트

```bash
# [로컬] OCI GG Admin Server URL 접속
# https://<GG_DEPLOYMENT_URL>/
# 사용자: oggadmin / Password: <설정값>
# 정상 접속 확인
```

### 1-3. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| Deployment 상태 | | ☐ ✅ ☐ ❌ | |
| GG 버전 (Oracle 19c SE 지원) | | ☐ ✅ ☐ ❌ | |
| 자동 업데이트 비활성화 | | ☐ ✅ ☐ ❌ | |
| Admin Server 로그인 | | ☐ ✅ ☐ ❌ | |

> **STEP 01 완료 서명**: __________________ 일시: __________________

---

## STEP 02. 소스/타겟 Connection 생성 및 연결 테스트

**목적**: OCI GG가 소스 RDS 및 타겟 DBCS에 정상 접속되는지 검증
**담당**: OCI GG 담당자
**예상 소요**: 30분
**실행 환경**: `[OCI콘솔]`, `[로컬]`

---

### 2-1. Credential Store 설정

```
-- [GG] GGSCI에서 실행
ADD CREDENTIALSTORE
ALTER CREDENTIALSTORE ADD USER ggadmin@<SRC_TNS_ALIAS> ALIAS ggadmin_src
ALTER CREDENTIALSTORE ADD USER ggadmin@<TGT_TNS_ALIAS> ALIAS ggadmin_tgt
INFO CREDENTIALSTORE
-- 두 개의 Alias 등록 확인
```

### 2-2. 소스 Connection 생성 (OCI콘솔)

```
[OCI콘솔] GoldenGate → Connections → Create Connection

[Source Connection]
  이름: SRC_RDS_CONN
  유형: Oracle Database
  Host: <RDS_ENDPOINT>
  Port: 1521
  Service Name: <RDS_SERVICE_NAME>
  Username: GGADMIN
  Password: <password>
  Wallet 파일: 해당 없음 (non-SSL)
```

### 2-3. 타겟 Connection 생성 (OCI콘솔)

```
[OCI콘솔] GoldenGate → Connections → Create Connection

[Target Connection]
  이름: TGT_DBCS_CONN
  유형: Oracle Database
  Host: <OCI_DBCS_PRIVATE_IP>
  Port: 1521
  Service Name: <DBCS_SERVICE_NAME>
  Username: GGADMIN
  Password: <password>
```

### 2-4. 네트워크 연결 테스트

```bash
# [로컬] OCI GG Deployment 호스트에서 소스 RDS 접근 가능 여부
telnet <RDS_ENDPOINT> 1521
# 또는
sqlplus GGADMIN/password@<RDS_ENDPOINT>:1521/<SERVICE>

# [로컬] OCI GG Deployment 호스트에서 타겟 DBCS 접근 가능 여부
telnet <OCI_DBCS_PRIVATE_IP> 1521
sqlplus GGADMIN/password@<OCI_DBCS_PRIVATE_IP>:1521/<SERVICE>
```

**기대값**: sqlplus 접속 성공, `SELECT 1 FROM DUAL;` 실행 가능

### 2-5. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| Credential Store 등록 (소스) | | ☐ ✅ ☐ ❌ | |
| Credential Store 등록 (타겟) | | ☐ ✅ ☐ ❌ | |
| 소스 Connection 생성 | | ☐ ✅ ☐ ❌ | |
| 타겟 Connection 생성 | | ☐ ✅ ☐ ❌ | |
| 소스 sqlplus 접속 테스트 | | ☐ ✅ ☐ ❌ | |
| 타겟 sqlplus 접속 테스트 | | ☐ ✅ ☐ ❌ | |

> **STEP 02 완료 서명**: __________________ 일시: __________________

---

## STEP 03. Heartbeat Table 추가

**목적**: GG End-to-End LAG를 정확히 측정하기 위한 Heartbeat 메커니즘 활성화
**담당**: OCI GG 담당자
**예상 소요**: 10분
**실행 환경**: `[GG]`

---

### 3-1. Heartbeat Table 생성

```
-- [GG] GGSCI에서 실행
ADD HEARTBEATTABLE
-- GG가 소스/타겟 양쪽에 Heartbeat 테이블 자동 생성
-- GGADMIN 계정으로 소스/타겟 각각 테이블 생성 확인
```

### 3-2. Heartbeat Table 확인

```
-- [GG] GGSCI에서 실행
INFO HEARTBEATTABLE
-- Heartbeat 테이블명 및 마지막 업데이트 시각 확인
```

```sql
-- [소스] Heartbeat 테이블 생성 확인
SELECT TABLE_NAME FROM DBA_TABLES WHERE OWNER = 'GGADMIN' AND TABLE_NAME LIKE '%HEARTBEAT%';
-- 기대값: GGS_HEARTBEAT 또는 GGS_LAG_HEARTBEAT 등 1건 이상

-- [타겟] 동일 확인
SELECT TABLE_NAME FROM DBA_TABLES WHERE OWNER = 'GGADMIN' AND TABLE_NAME LIKE '%HEARTBEAT%';
```

### 3-3. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| Heartbeat Table 생성 (소스) | | ☐ ✅ ☐ ❌ | |
| Heartbeat Table 생성 (타겟) | | ☐ ✅ ☐ ❌ | |
| INFO HEARTBEATTABLE 정상 응답 | | ☐ ✅ ☐ ❌ | |

> **STEP 03 완료 서명**: __________________ 일시: __________________

---

## STEP 04. Extract (EXT1) 파라미터 설정 및 등록

**목적**: 소스 RDS Redo Log에서 변경 데이터를 추출하는 Extract 프로세스 설정
**담당**: OCI GG 담당자
**예상 소요**: 30분
**실행 환경**: `[GG]`

> **중요**: Extract는 이 단계에서 등록하되, **실제 시작(START)은 STEP 09에서 expdp SCN 기록 후 수행**

---

### 4-1. Extract Trail 등록

```
-- [GG] GGSCI에서 실행
ADD EXTRACT EXT1, INTEGRATED TRANLOG, BEGIN NOW
ADD EXTTRAIL ./dirdat/aa, EXTRACT EXT1, MEGABYTES 500
```

### 4-2. Extract 파라미터 파일 작성

```
-- [GG] GGSCI에서 실행
EDIT PARAMS EXT1
```

```
-- Extract 파라미터 내용 (전체 DB 이전 — 시스템 스키마 제외)
EXTRACT EXT1
USERIDALIAS ggadmin_src DOMAIN OracleGoldenGate
EXTTRAIL ./dirdat/aa
SOURCETIMEZONE +09:00

-- SE 제약: 지원 범위 내 DDL 복제만 설정
DDL INCLUDE MAPPED OBJTYPE 'TABLE' OPTYPE CREATE, ALTER, DROP, TRUNCATE

-- 시스템 스키마 명시적 제외 (와일드카드 TABLE *.* 와 함께 사용)
TABLEEXCLUDE SYS.*;
TABLEEXCLUDE SYSTEM.*;
TABLEEXCLUDE OUTLN.*;
TABLEEXCLUDE DBSNMP.*;
TABLEEXCLUDE APPQOSSYS.*;
TABLEEXCLUDE AUDSYS.*;
TABLEEXCLUDE CTXSYS.*;
TABLEEXCLUDE DBSFWUSER.*;
TABLEEXCLUDE DVSYS.*;
TABLEEXCLUDE EXFSYS.*;
TABLEEXCLUDE GGSYS.*;
TABLEEXCLUDE GSMADMIN_INTERNAL.*;
TABLEEXCLUDE LBACSYS.*;
TABLEEXCLUDE MDSYS.*;
TABLEEXCLUDE OJVMSYS.*;
TABLEEXCLUDE OLAPSYS.*;
TABLEEXCLUDE ORDDATA.*;
TABLEEXCLUDE ORDSYS.*;
TABLEEXCLUDE WMSYS.*;
TABLEEXCLUDE XDB.*;
-- GoldenGate 자체 스키마 반드시 제외
TABLEEXCLUDE GGADMIN.*;
TABLEEXCLUDE GGS_TEMP.*;

-- 전체 사용자 스키마 복제 (와일드카드)
TABLE *.*;
SEQUENCE *.*;
```

> **주의사항**
> - XMLTYPE Object-Relational 방식 테이블 존재 시 해당 테이블 TABLEEXCLUDE 추가 필요
> - SE 환경에서 GG DDL 복제는 지원 범위가 제한됨 → 미지원 DDL 발생 시 수동 처리 절차 별도 수립

### 4-3. Extract 파라미터 검증

```
-- [GG] GGSCI에서 실행
VIEW PARAMS EXT1
-- 파라미터 파일 내용 확인 (저장 완료 여부)

INFO EXTRACT EXT1
-- 상태: STOPPED (아직 START 하지 않음 — 정상)
```

### 4-4. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| ADD EXTRACT EXT1 등록 | | ☐ ✅ ☐ ❌ | |
| ADD EXTTRAIL 등록 | | ☐ ✅ ☐ ❌ | |
| 파라미터 파일 저장 확인 | | ☐ ✅ ☐ ❌ | |
| TABLEEXCLUDE 시스템 스키마 전체 포함 | | ☐ ✅ ☐ ❌ | |
| TABLE *.* / SEQUENCE *.* 설정 | | ☐ ✅ ☐ ❌ | |

> **STEP 04 완료 서명**: __________________ 일시: __________________

---

## STEP 05. Data Pump (PUMP1) 파라미터 설정 및 등록

**목적**: Extract Trail 파일을 OCI Object Storage의 Remote Trail로 전송하는 Pump 설정
**담당**: OCI GG 담당자
**예상 소요**: 20분
**실행 환경**: `[GG]`

---

### 5-1. OCI Object Storage Trail 경로 확인

```
[OCI콘솔] Object Storage → 버킷 목록
  - Trail File 저장 버킷명 확인: <TRAIL_BUCKET>
  - OCI GG Trail 경로 확인: oci://<TRAIL_BUCKET>@<NAMESPACE>/trail/rt
```

### 5-2. Pump 등록 및 파라미터 작성

```
-- [GG] GGSCI에서 실행
ADD EXTRACT PUMP1, EXTTRAILSOURCE ./dirdat/aa
ADD RMTTRAIL oci://<TRAIL_BUCKET>@<NAMESPACE>/trail/rt, EXTRACT PUMP1
```

```
-- [GG] GGSCI에서 실행
EDIT PARAMS PUMP1
```

```
-- Pump 파라미터 내용
EXTRACT PUMP1
USERIDALIAS ggadmin_src DOMAIN OracleGoldenGate
RMTTRAIL oci://<TRAIL_BUCKET>@<NAMESPACE>/trail/rt
PASSTHRU

-- Extract와 동일한 범위 (PASSTHRU 모드에서는 와일드카드 사용)
TABLE *.*;
SEQUENCE *.*;
```

### 5-3. OCI Object Storage 연결 확인

```sql
-- [소스] OCI GG가 Object Storage에 접근 가능한지 확인
-- (OCI GG Deployment IAM Policy에서 Object Storage 접근 권한 부여 여부)
```

```
-- [GG] GGSCI에서 실행
INFO EXTRACT PUMP1, DETAIL
-- Trail 저장소 경로 정상 등록 확인
```

### 5-4. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| ADD EXTRACT PUMP1 등록 | | ☐ ✅ ☐ ❌ | |
| ADD RMTTRAIL Object Storage 경로 설정 | | ☐ ✅ ☐ ❌ | |
| PASSTHRU 파라미터 설정 | | ☐ ✅ ☐ ❌ | |
| Object Storage 접근 권한 (IAM Policy) | | ☐ ✅ ☐ ❌ | |

> **STEP 05 완료 서명**: __________________ 일시: __________________

---

## STEP 06. Replicat (REP1) 파라미터 설정 및 등록

**목적**: OCI Object Storage Trail을 읽어 타겟 DBCS에 변경 데이터를 적용하는 Replicat 설정
**담당**: OCI GG 담당자
**예상 소요**: 30분
**실행 환경**: `[GG]`

> **중요**: Replicat은 이 단계에서 등록하되, **실제 시작(START)은 STEP 16에서 GG 복제 시작 시 수행**

---

### 6-1. Replicat 등록

```
-- [GG] GGSCI에서 실행
ADD REPLICAT REP1, INTEGRATED, EXTTRAIL oci://<TRAIL_BUCKET>@<NAMESPACE>/trail/rt
```

### 6-2. Replicat 파라미터 파일 작성

```
-- [GG] GGSCI에서 실행
EDIT PARAMS REP1
```

```
-- Replicat 파라미터 내용
REPLICAT REP1
USERIDALIAS ggadmin_tgt DOMAIN OracleGoldenGate
SOURCETIMEZONE +09:00

-- 소스/타겟 구조 완전 동일한 경우 ASSUMETARGETDEFS 사용
-- Tablespace 리맵핑 등 구조 변경이 있으면 DEFS 파일 생성 후 SOURCEDEFS 사용
ASSUMETARGETDEFS

-- Trigger 이중 실행 방지 (필수 — GG Replicat 세션에서 Trigger 비활성화)
SUPPRESSTRIGGERS

-- 초기 적재(impdp) 데이터와의 충돌 자동 처리 (데이터 동기화 완료 후 반드시 제거)
HANDLECOLLISIONS

-- 전체 DB 이전: 와일드카드로 전체 사용자 스키마 매핑
-- (시스템 스키마는 Extract에서 이미 제외 → Trail에 포함되지 않음)
MAP *.*, TARGET *.*;
SEQUENCE *.*;
```

> **HANDLECOLLISIONS 주의사항**:
> - 초기 데이터 적재(impdp) 이후 GG 복제 시작 시 중복 데이터 충돌 방지용
> - **GG 동기화가 완전히 안정화된 후 (LAG < 30초, 24h 유지) 반드시 제거**
> - 제거 방법: STOP REPLICAT REP1 → EDIT PARAMS REP1 (해당 줄 삭제) → START REPLICAT REP1

### 6-3. Replicat 파라미터 검증

```
-- [GG] GGSCI에서 실행
VIEW PARAMS REP1
-- 파라미터 파일 내용 확인

INFO REPLICAT REP1
-- 상태: STOPPED (아직 START 하지 않음 — 정상)
```

### 6-4. SUPPRESSTRIGGERS 적용 확인

```sql
-- [타겟] GG Replicat 세션에서 Trigger가 실행되지 않는지 확인
-- (GG 시작 후 STATS REPLICAT REP1으로 간접 확인 가능)
-- Trigger가 있는 테이블에 대해 타겟 Trigger DISABLE도 병행 적용 (Phase 4에서 수행)
```

### 6-5. Phase 3 완료 체크리스트

| 항목 | 기대값 | 확인 결과 | 판정 | 확인자 |
|------|--------|-----------|------|--------|
| OCI GG Deployment 정상 동작 | Active | | ☐ ✅ ☐ ❌ | |
| 소스 Connection 연결 테스트 | PASS | | ☐ ✅ ☐ ❌ | |
| 타겟 Connection 연결 테스트 | PASS | | ☐ ✅ ☐ ❌ | |
| Heartbeat Table 소스/타겟 생성 | 각 1건 이상 | | ☐ ✅ ☐ ❌ | |
| Extract EXT1 등록 (STOPPED) | STOPPED | | ☐ ✅ ☐ ❌ | |
| Pump PUMP1 등록 (STOPPED) | STOPPED | | ☐ ✅ ☐ ❌ | |
| Replicat REP1 등록 (STOPPED) | STOPPED | | ☐ ✅ ☐ ❌ | |
| Trail File 저장소 (Object Storage) 연결 | PASS | | ☐ ✅ ☐ ❌ | |

**Phase 3 완료 승인**

| 역할 | 성명 | 서명 | 일시 |
|------|------|------|------|
| 마이그레이션 리더 | | | |
| OCI GG 담당자 | | | |

> **Phase 3 → Phase 4 전환 조건**: 위 체크리스트 전 항목 ✅ 완료

---

# Phase 4: 초기 데이터 적재 (expdp / impdp)

---

## STEP 07. UNDO / Flashback 사전 확인

**목적**: expdp FLASHBACK_SCN 사용 전 UNDO 충분성 검증
**담당**: 소스 DBA
**예상 소요**: 15분
**실행 환경**: `[소스]`

---

### 7-1. UNDO 파라미터 확인

```sql
-- [소스] 실행
-- UNDO_RETENTION 확인 (Export 예상 소요시간 + 여유분 이상이어야 함)
SELECT NAME, VALUE FROM V$PARAMETER
WHERE NAME IN ('undo_retention', 'undo_tablespace');
```

| 항목 | 소스 설정값 | 필요값 | 판정 |
|------|------------|--------|------|
| undo_retention | | Export 소요시간(초) + 3600 이상 | ☐ ✅ ☐ ❌ |

> **undo_retention 부족 시**: `ALTER SYSTEM SET UNDO_RETENTION=<seconds> SCOPE=BOTH;`
> AWS RDS에서 변경 제한될 경우: FLASHBACK_TIME 파라미터 사용 또는 야간 저부하 시간대 Export 권장

### 7-2. UNDO 테이블스페이스 여유 공간 확인

```sql
-- [소스] 실행
SELECT TABLESPACE_NAME,
       ROUND(SUM(BYTES)/1024/1024/1024, 2) AS FREE_GB
FROM DBA_FREE_SPACE
WHERE TABLESPACE_NAME LIKE '%UNDO%'
GROUP BY TABLESPACE_NAME;
```

| 항목 | 현재 여유 공간 | 기준 | 판정 |
|------|--------------|------|------|
| UNDO 여유 공간 | | DB 크기의 10% 이상 | ☐ ✅ ☐ ❌ |

### 7-3. MIGRATION_USER Flashback 권한 확인

```sql
-- [소스] 실행
SELECT GRANTEE, PRIVILEGE FROM DBA_SYS_PRIVS
WHERE GRANTEE = 'MIGRATION_USER'
AND PRIVILEGE IN ('FLASHBACK ANY TABLE', 'EXP_FULL_DATABASE');
```

**기대값**: `FLASHBACK ANY TABLE`, `EXP_FULL_DATABASE` 모두 조회

### 7-4. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| UNDO_RETENTION ≥ 예상 Export 시간 + 여유분 | | ☐ ✅ ☐ ❌ | |
| UNDO 테이블스페이스 여유 공간 충분 | | ☐ ✅ ☐ ❌ | |
| MIGRATION_USER Flashback 권한 확인 | | ☐ ✅ ☐ ❌ | |

> **STEP 07 완료 서명**: __________________ 일시: __________________

---

## STEP 08. expdp SCN 고정 및 Export SCN 기록

**목적**: expdp DATA_ONLY Export의 기준 SCN을 결정하고 기록
**담당**: 소스 DBA, OCI GG 담당자
**예상 소요**: 10분
**실행 환경**: `[소스]`

> **중요**: 이 SCN이 expdp FLASHBACK_SCN 값과 GG Extract 시작점의 기준이 됨

---

### 8-1. Export 직전 SCN 확인

```sql
-- [소스] expdp 실행 직전에 실행
SELECT CURRENT_SCN, TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS SNAPSHOT_TIME
FROM V$DATABASE;
```

**SCN 기록**:

| 항목 | 값 | 기록자 | 기록 일시 |
|------|-----|--------|-----------|
| FLASHBACK_SCN | | | |
| SNAPSHOT_TIME | | | |
| 소스 DB 호스트명 | | | |

> **이 SCN 값은 STEP 09 (GG Extract SCN 재등록)와 STEP 10 (expdp FLASHBACK_SCN)에서 사용**

> **STEP 08 완료 서명**: __________________ 일시: __________________

---

## STEP 09. Extract SCN 기준점 재등록

**목적**: expdp SCN을 기준으로 GG Extract가 해당 시점부터 추출을 시작하도록 설정
**담당**: OCI GG 담당자
**예상 소요**: 10분
**실행 환경**: `[GG]`

---

### 9-1. 기존 Extract 삭제 후 SCN 지정하여 재등록

```
-- [GG] GGSCI에서 실행
-- 기존 EXT1 삭제 (STEP 04에서 등록한 것 — BEGIN NOW로 등록된 것)
STOP EXTRACT EXT1   (이미 STOPPED이면 불필요)
DELETE EXTRACT EXT1

-- SCN을 지정하여 재등록 (STEP 08에서 기록한 SCN 사용)
ADD EXTRACT EXT1, INTEGRATED TRANLOG, BEGIN SCN <FLASHBACK_SCN>
ADD EXTTRAIL ./dirdat/aa, EXTRACT EXT1, MEGABYTES 500
-- 예: ADD EXTRACT EXT1, INTEGRATED TRANLOG, BEGIN SCN 98765432
```

### 9-2. Extract SCN 기준점 확인

```
-- [GG] GGSCI에서 실행
INFO EXTRACT EXT1, DETAIL
-- "Begin SCN: <FLASHBACK_SCN>" 확인
-- 상태: STOPPED (아직 START 하지 않음 — 정상)
```

### 9-3. 결과 기록

| 항목 | 설정값 | 판정 | 확인자 |
|------|--------|------|--------|
| Extract 재등록 SCN | | ☐ ✅ ☐ ❌ | |
| INFO EXTRACT SCN 확인 | | ☐ ✅ ☐ ❌ | |

> **STEP 09 완료 서명**: __________________ 일시: __________________

---

## STEP 10. DATA_ONLY expdp Export 실행

**목적**: STEP 08에서 기록한 SCN을 기준으로 전체 DB 데이터를 Export
**담당**: 소스 DBA
**예상 소요**: DB 크기에 따라 수 시간 ~ 수십 시간
**실행 환경**: `[소스]`

---

### 10-1. Export Directory 확인

```sql
-- [소스] 실행
SELECT DIRECTORY_NAME, DIRECTORY_PATH FROM DBA_DIRECTORIES
WHERE DIRECTORY_NAME = 'DATA_PUMP_DIR';
-- RDS 기본 경로: /rdsdbdata/userdirs/01/
```

### 10-2. expdp DATA_ONLY 실행

```bash
# [소스] 실행 (백그라운드 또는 tmux/screen 세션에서 실행 권장)
nohup expdp MIGRATION_USER/password@RDS_TNS \
    FULL=Y \
    CONTENT=DATA_ONLY \
    FLASHBACK_SCN=<STEP_08_SCN> \
    DUMPFILE=fulldata_%U.dmp \
    FILESIZE=10G \
    PARALLEL=1 \
    LOGFILE=fulldata_export.log \
    EXCLUDE=STATISTICS \
    DIRECTORY=DATA_PUMP_DIR \
> /tmp/expdp_run.log 2>&1 &

echo "expdp PID: $!"
```

> **PARALLEL 주의사항**: Oracle SE에서 PARALLEL 파라미터 효과가 제한적. PARALLEL=1로 시작하고 성능 확인 후 조정.

### 10-3. Export 진행 모니터링

```bash
# [소스] 별도 세션에서 주기적 확인
tail -f /rdsdbdata/userdirs/01/fulldata_export.log

# 또는 sqlplus에서 진행 상태 확인
sqlplus MIGRATION_USER/password@RDS_TNS
```

```sql
-- [소스] expdp 진행 상태 확인
SELECT JOB_NAME, STATE, DEGREE, PERCENT_DONE
FROM DBA_DATAPUMP_JOBS
WHERE STATE != 'NOT RUNNING';
```

### 10-4. Export 완료 확인

```bash
# [소스] Export 로그 마지막 줄 확인
tail -50 /rdsdbdata/userdirs/01/fulldata_export.log
# 기대값: "Job "MIGRATION_USER"."SYS_EXPORT_FULL_..." successfully completed"
```

```sql
-- [소스] Export된 Dump 파일 목록 및 크기 확인
SELECT FILE_NAME, FILE_SIZE/1024/1024/1024 AS GB
FROM EXTERNAL_TAB_PARTITIONS
-- 또는 OS 레벨에서:
-- ls -lh /rdsdbdata/userdirs/01/fulldata_*.dmp
```

### 10-5. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| expdp 오류 0건 | | ☐ ✅ ☐ ⚠️ ☐ ❌ | |
| "successfully completed" 메시지 | | ☐ ✅ ☐ ❌ | |
| FLASHBACK_SCN 사용 확인 | | ☐ ✅ ☐ ❌ | |
| Dump 파일 크기 확인 (예상 크기와 대비) | | ☐ ✅ ☐ ⚠️ | |

> ⚠️ **허용 가능한 오류**: ORA-39166 (오브젝트 미발견 — 삭제된 임시 오브젝트), ORA-31693 (일부 오브젝트 Export 실패 — 원인 분석 필요)

> **STEP 10 완료 서명**: __________________ 일시: __________________

---

## STEP 11. Dump 파일 OCI Object Storage 전송

**목적**: 소스 RDS의 Dump 파일을 OCI Object Storage를 경유하여 타겟 DBCS로 전송
**담당**: 소스 DBA, 인프라 담당
**예상 소요**: 네트워크 대역폭에 따라 수 시간
**실행 환경**: `[소스]`, `[타겟]`

---

### 11-1. OCI CLI 설정 확인 (소스 측)

```bash
# [소스] OCI CLI 설치 및 인증 확인
oci --version
oci os ns get   # Namespace 확인
# 기대값: {"data": "<namespace>"}
```

### 11-2. Dump 파일 OCI Object Storage 업로드

```bash
# [소스] 실행
oci os object bulk-upload \
    --bucket-name <DUMP_BUCKET> \
    --src-dir /rdsdbdata/userdirs/01/ \
    --include "fulldata_*.dmp" \
    --prefix fulldata/ \
    --multipart-threshold 100MB \
    --parallel-upload-count 3

# 통계 Export 파일도 함께 업로드 (01.pre_migration.md STEP 24에서 생성)
oci os object bulk-upload \
    --bucket-name <DUMP_BUCKET> \
    --src-dir /rdsdbdata/userdirs/01/ \
    --include "stats_export.dmp" \
    --prefix stats/
```

### 11-3. 업로드 완료 및 파일 무결성 확인

```bash
# [로컬] OCI Object Storage 오브젝트 목록 확인
oci os object list \
    --bucket-name <DUMP_BUCKET> \
    --prefix fulldata/ \
    --query 'data[].{name:name, size:size}' \
    --output table

# MD5 체크섬 비교 (선택 사항 — 대용량 파일 무결성 확인)
oci os object head \
    --bucket-name <DUMP_BUCKET> \
    --name fulldata/fulldata_01.dmp
```

### 11-4. 타겟 DBCS로 Dump 파일 다운로드

```bash
# [타겟] 실행
oci os object bulk-download \
    --bucket-name <DUMP_BUCKET> \
    --download-dir /u01/backup/dump/ \
    --prefix fulldata/ \
    --parallel-download-count 3

# 통계 Export 파일 다운로드
oci os object bulk-download \
    --bucket-name <DUMP_BUCKET> \
    --download-dir /u01/backup/dump/ \
    --prefix stats/
```

### 11-5. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| OCI Object Storage 업로드 완료 | | ☐ ✅ ☐ ❌ | |
| 파일 개수 소스/타겟 일치 | | ☐ ✅ ☐ ❌ | |
| 타겟 DBCS 다운로드 완료 | | ☐ ✅ ☐ ❌ | |
| 디스크 여유 공간 충분 (Dump 크기 × 2 이상) | | ☐ ✅ ☐ ❌ | |

> **STEP 11 완료 서명**: __________________ 일시: __________________

---

## STEP 12. 타겟 FK/Trigger DISABLE 및 impdp Import 실행

**목적**: 참조 무결성 오류 없이 데이터를 적재하기 위해 FK/Trigger를 비활성화 후 impdp 실행
**담당**: 타겟 DBA
**예상 소요**: DB 크기에 따라 수 시간 ~ 수십 시간
**실행 환경**: `[타겟]`

---

### 12-1. FK Constraint 비활성화

```bash
# [타겟] sqlplus에서 FK DISABLE 스크립트 생성 및 실행
sqlplus MIGRATION_USER/password@OCI_TNS <<'EOF'
SPOOL /tmp/disable_fk.sql
SELECT 'ALTER TABLE '||OWNER||'.'||TABLE_NAME||
       ' DISABLE CONSTRAINT '||CONSTRAINT_NAME||';'
FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL',
    'GGADMIN','GGS_TEMP','MIGRATION_USER'
)
ORDER BY OWNER, TABLE_NAME;
SPOOL OFF
@/tmp/disable_fk.sql
COMMIT;
EOF
```

```sql
-- [타겟] FK DISABLE 적용 건수 확인
SELECT COUNT(*) AS DISABLED_FK_CNT
FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R'
AND STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 소스의 FK 제약 건수와 동일
```

### 12-2. Trigger 비활성화

```bash
# [타겟] 01.pre_migration.md STEP 23에서 준비한 disable_triggers.sql 실행
sqlplus MIGRATION_USER/password@OCI_TNS @/tmp/disable_triggers.sql
```

```sql
-- [타겟] Trigger DISABLE 적용 확인
SELECT COUNT(*) AS ENABLED_TRIGGER_CNT
FROM DBA_TRIGGERS
WHERE STATUS = 'ENABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건 (모든 Trigger DISABLED)
```

### 12-3. impdp DATA_ONLY 실행

```bash
# [타겟] Import Directory 확인
# SELECT DIRECTORY_NAME, DIRECTORY_PATH FROM DBA_DIRECTORIES WHERE DIRECTORY_NAME='DATA_PUMP_DIR';

# [타겟] impdp 실행 (백그라운드)
nohup impdp MIGRATION_USER/password@OCI_TNS \
    FULL=Y \
    CONTENT=DATA_ONLY \
    DUMPFILE=fulldata_%U.dmp \
    PARALLEL=1 \
    LOGFILE=fulldata_import.log \
    TABLE_EXISTS_ACTION=TRUNCATE \
    REMAP_TABLESPACE=<SOURCE_TS>:<TARGET_TS> \
    DIRECTORY=DATA_PUMP_DIR \
> /tmp/impdp_run.log 2>&1 &

echo "impdp PID: $!"
```

> **TABLE_EXISTS_ACTION=TRUNCATE 주의사항**:
> - 타겟 테이블을 TRUNCATE 후 INSERT — FK가 이미 DISABLE되어 있어야 함 (12-1에서 완료)
> - CONTENT=DATA_ONLY이므로 테이블 구조(DDL)는 변경하지 않음

### 12-4. Import 진행 모니터링

```bash
# [타겟] 별도 세션에서 주기적 확인
tail -f <DATA_PUMP_DIR_PATH>/fulldata_import.log

# sqlplus에서 진행 상태 확인
```

```sql
-- [타겟] impdp 진행 상태 확인
SELECT JOB_NAME, STATE, DEGREE, PERCENT_DONE
FROM DBA_DATAPUMP_JOBS
WHERE STATE != 'NOT RUNNING';
```

### 12-5. Import 완료 확인

```bash
# [타겟] Import 로그 마지막 줄 확인
tail -50 <DATA_PUMP_DIR_PATH>/fulldata_import.log
# 기대값: "Job "MIGRATION_USER"."SYS_IMPORT_FULL_..." successfully completed"
```

### 12-6. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| FK DISABLE 완료 (모든 FK) | | ☐ ✅ ☐ ❌ | |
| Trigger DISABLE 완료 (모든 Trigger) | | ☐ ✅ ☐ ❌ | |
| impdp 오류 0건 | | ☐ ✅ ☐ ⚠️ ☐ ❌ | |
| "successfully completed" 메시지 | | ☐ ✅ ☐ ❌ | |

> ⚠️ **허용 가능한 오류**: ORA-31684 (이미 존재하는 오브젝트 — DATA_ONLY이므로 무시 가능), ORA-39083 (특정 오브젝트 생성 실패 — 원인 분석 필요)

> **STEP 12 완료 서명**: __________________ 일시: __________________

---

## STEP 13. 통계정보 Import (옵션 A)

**목적**: 소스에서 Export한 통계정보를 타겟에 Import하여 옵티마이저 계획 정합성 확보
**담당**: 타겟 DBA
**예상 소요**: 30분 ~ 1시간
**실행 환경**: `[타겟]`

> **전제**: 01.pre_migration.md STEP 24에서 소스의 STATS_EXPORT_TABLE을 stats_export.dmp로 Export하고 OCI Object Storage에 업로드 완료 (STEP 11에서 타겟 다운로드 완료)

---

### 13-1. STATS_EXPORT_TABLE impdp Import

```bash
# [타겟] 통계 스테이징 테이블 Import
impdp MIGRATION_USER/password@OCI_TNS \
    TABLES=MIGRATION_USER.STATS_EXPORT_TABLE \
    DUMPFILE=stats_export.dmp \
    LOGFILE=stats_import.log \
    TABLE_EXISTS_ACTION=REPLACE \
    DIRECTORY=DATA_PUMP_DIR
```

### 13-2. 전체 DB 통계 Import

```sql
-- [타겟] 실행
-- 전체 DB 통계 일괄 Import (소스 통계정보 타겟에 적용)
BEGIN
    DBMS_STATS.IMPORT_DATABASE_STATS(
        stattab => 'STATS_EXPORT_TABLE',
        statown => 'MIGRATION_USER',
        force   => TRUE     -- 기존 통계 덮어쓰기
    );
END;
/
```

### 13-3. 통계 Import 결과 확인

```sql
-- [타겟] 스키마별 통계 존재 현황
SELECT OWNER,
       COUNT(*) AS TABLE_CNT,
       SUM(CASE WHEN LAST_ANALYZED IS NULL THEN 1 ELSE 0 END) AS NO_STATS_CNT
FROM DBA_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL'
)
GROUP BY OWNER
ORDER BY NO_STATS_CNT DESC;
-- 기대값: 모든 스키마 NO_STATS_CNT = 0
```

### 13-4. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| STATS_EXPORT_TABLE impdp 완료 | | ☐ ✅ ☐ ❌ | |
| IMPORT_DATABASE_STATS 완료 | | ☐ ✅ ☐ ❌ | |
| 통계 없는 테이블 0건 (NO_STATS_CNT = 0) | | ☐ ✅ ☐ ⚠️ | |

> **STEP 13 완료 서명**: __________________ 일시: __________________

---

## STEP 14. Import 후 오브젝트 상태 확인

**목적**: impdp DATA_ONLY 적재 후 INVALID 객체 및 UNUSABLE 인덱스 점검 및 해소
**담당**: 타겟 DBA
**예상 소요**: 30분 ~ 1시간
**실행 환경**: `[타겟]`

---

### 14-1. INVALID 객체 전수 확인 및 재컴파일

```sql
-- [타겟] INVALID 객체 확인
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS, LAST_DDL_TIME
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL'
)
ORDER BY OWNER, OBJECT_TYPE;
-- INVALID 존재 시 → 14-2 재컴파일 수행
```

**INVALID 건수 기록**: ______ 건

### 14-2. 전체 DB 재컴파일 (INVALID 존재 시)

```sql
-- [타겟] 실행 (INVALID 존재 시)
BEGIN
    FOR u IN (
        SELECT USERNAME FROM DBA_USERS
        WHERE USERNAME NOT IN (
            'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
            'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER',
            'GSMUSER','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
            'ORDPLUGINS','ORDSYS','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA',
            'SYS$UMF','SYSBACKUP','SYSDG','SYSKM','SYSRAC','WMSYS','XDB','XS$NULL',
            'GGADMIN','GGS_TEMP','MIGRATION_USER'
        )
        AND ACCOUNT_STATUS = 'OPEN'
        ORDER BY USERNAME
    ) LOOP
        DBMS_UTILITY.COMPILE_SCHEMA(schema => u.USERNAME, compile_all => FALSE);
    END LOOP;
END;
/
```

```sql
-- [타겟] 재컴파일 후 재확인 — 기대값: 0건
SELECT COUNT(*) AS STILL_INVALID
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);
```

> 재컴파일 후에도 INVALID 잔존 시: 개별 오브젝트 오류 메시지 확인
> ```sql
> ALTER PROCEDURE <OWNER>.<PROC_NAME> COMPILE;
> -- 오류 확인: SELECT * FROM USER_ERRORS;
> ```

### 14-3. 인덱스 UNUSABLE 확인 및 재빌드

```sql
-- [타겟] 전체 인덱스 상태 확인
SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS, PARTITIONED
FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건

-- [타겟] 파티션 인덱스 파티션별 상태
SELECT INDEX_OWNER, INDEX_NAME, PARTITION_NAME, STATUS
FROM DBA_IND_PARTITIONS
WHERE STATUS != 'USABLE'
AND INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건
```

```sql
-- [타겟] UNUSABLE 인덱스 발견 시 재빌드
ALTER INDEX <OWNER>.<INDEX_NAME> REBUILD;
-- 파티션 인덱스의 경우:
ALTER INDEX <OWNER>.<INDEX_NAME> REBUILD PARTITION <PARTITION_NAME>;
```

### 14-4. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| INVALID 객체 0건 (재컴파일 후) | | ☐ ✅ ☐ ❌ | |
| UNUSABLE 인덱스 0건 (재빌드 후) | | ☐ ✅ ☐ ❌ | |
| UNUSABLE 파티션 인덱스 0건 | | ☐ ✅ ☐ ❌ | |

> **STEP 14 완료 서명**: __________________ 일시: __________________

---

## STEP 15. Import 후 초기 Row Count 확인

**목적**: expdp SCN 고정 기준으로 소스/타겟 Row Count 일치 여부 검증
**담당**: 소스 DBA, 타겟 DBA
**예상 소요**: 30분 ~ 1시간 (테이블 규모에 따라)
**실행 환경**: `[소스]`, `[타겟]`

---

### 15-1. 전체 테이블 Row Count 비교 스크립트 생성

```sql
-- [소스] / [타겟] 각각 동일하게 실행
-- 핵심 테이블 대상 COUNT(*) 스크립트 생성
SELECT 'SELECT ''' || OWNER || '.' || TABLE_NAME || ''' AS TBL, COUNT(*) AS CNT FROM ' ||
       OWNER || '.' || TABLE_NAME || ';'
FROM DBA_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL',
    'GGADMIN','GGS_TEMP','MIGRATION_USER'
)
ORDER BY OWNER, TABLE_NAME;
-- 생성된 스크립트 실행 후 소스/타겟 결과 비교
```

### 15-2. Row Count 비교 결과 기록

| 스키마 | 테이블 | 소스 COUNT | 타겟 COUNT | 차이 | 판정 |
|--------|--------|------------|------------|------|------|
| | | | | | ☐ ✅ ☐ ❌ |
| | | | | | ☐ ✅ ☐ ❌ |
| | | | | | ☐ ✅ ☐ ❌ |

> **기대값**: FLASHBACK_SCN 시점 기준 DATA_ONLY import이므로 소스/타겟 COUNT 완전 일치

### 15-3. Phase 4 완료 체크리스트

| 항목 | 기대값 | 확인 결과 | 판정 | 확인자 |
|------|--------|-----------|------|--------|
| expdp Export 오류 0건 | 0건 | | ☐ ✅ ☐ ❌ | |
| impdp Import 오류 0건 (허용 가능 오류 제외) | 0건 | | ☐ ✅ ☐ ❌ | |
| FK DISABLE 완료 | 전체 FK DISABLED | | ☐ ✅ ☐ ❌ | |
| Trigger DISABLE 완료 | 전체 Trigger DISABLED | | ☐ ✅ ☐ ❌ | |
| 통계정보 Import 완료 (NO_STATS = 0) | 0건 | | ☐ ✅ ☐ ❌ | |
| INVALID 객체 0건 | 0건 | | ☐ ✅ ☐ ❌ | |
| UNUSABLE 인덱스 0건 | 0건 | | ☐ ✅ ☐ ❌ | |
| Row Count 소스/타겟 일치 (핵심 테이블) | 0% 오차 | | ☐ ✅ ☐ ❌ | |

**Phase 4 완료 승인**

| 역할 | 성명 | 서명 | 일시 |
|------|------|------|------|
| 마이그레이션 리더 | | | |
| 소스 DBA | | | |
| 타겟 DBA | | | |

> **Phase 4 → Phase 5 전환 조건**: 위 체크리스트 전 항목 ✅ 완료

---

# Phase 5: 델타 동기화 (OCI GG 복제)

---

## STEP 16. GG 복제 시작 (ATCSN)

**목적**: expdp SCN 기준점부터 GG 복제를 시작하여 소스/타겟 동기화 개시
**담당**: OCI GG 담당자
**예상 소요**: 15분 (시작 확인까지)
**실행 환경**: `[GG]`

---

### 16-1. Extract 시작 (SCN 기준점)

```
-- [GG] GGSCI에서 실행
-- ATCSN: 해당 SCN을 포함하는 트랜잭션부터 적용 (expdp 경계 데이터 누락 방지)
-- ※ AFTERCSN은 해당 SCN 이후부터 — expdp와 경계에서 데이터 누락 가능성 있음 → 사용 금지
START EXTRACT EXT1 ATCSN <FLASHBACK_SCN>
-- 예: START EXTRACT EXT1 ATCSN 98765432
```

```
-- [GG] Extract 상태 확인
STATUS EXTRACT EXT1
-- 기대값: RUNNING
```

### 16-2. Pump 시작

```
-- [GG] GGSCI에서 실행
START EXTRACT PUMP1

-- Pump 상태 확인
STATUS EXTRACT PUMP1
-- 기대값: RUNNING
```

### 16-3. Replicat 시작 (HANDLECOLLISIONS 활성 상태로 시작)

```
-- [GG] GGSCI에서 실행
-- HANDLECOLLISIONS 파라미터가 REP1에 설정된 상태로 시작
-- (impdp 데이터와 GG 복제 데이터 충돌 자동 처리)
START REPLICAT REP1

-- Replicat 상태 확인
STATUS REPLICAT REP1
-- 기대값: RUNNING
```

### 16-4. 초기 상태 확인

```
-- [GG] GGSCI에서 실행 (3개 프로세스 모두 RUNNING 확인)
INFO ALL
-- Extract EXT1:  RUNNING
-- Extract PUMP1: RUNNING
-- Replicat REP1: RUNNING
```

### 16-5. 결과 기록

| 프로세스 | 시작 시각 | 상태 | 판정 | 확인자 |
|---------|---------|------|------|--------|
| EXT1 | | | ☐ ✅ ☐ ❌ | |
| PUMP1 | | | ☐ ✅ ☐ ❌ | |
| REP1 | | | ☐ ✅ ☐ ❌ | |
| ATCSN 값 | | | ☐ ✅ ☐ ❌ | |

> **STEP 16 완료 서명**: __________________ 일시: __________________

---

## STEP 17. GG 프로세스 상태 초기 확인

**목적**: GG 복제 시작 후 30분 이내 초기 이상 여부 점검
**담당**: OCI GG 담당자
**예상 소요**: 30분
**실행 환경**: `[GG]`

---

### 17-1. Extract 상태 확인

```
-- [GG] GGSCI에서 실행
STATUS EXTRACT EXT1
-- 기대값: RUNNING

LAG EXTRACT EXT1
-- 초기에는 LAG이 높을 수 있음 (expdp 이후 누적 변경분 처리 중) → 점차 감소 확인

INFO EXTRACT EXT1, DETAIL
-- Checkpoint SCN이 증가하는지 확인

VIEW REPORT EXT1
-- ABEND/ERROR 없음 확인
```

### 17-2. Pump 상태 확인

```
-- [GG] GGSCI에서 실행
STATUS EXTRACT PUMP1
LAG EXTRACT PUMP1

-- Trail 파일 Object Storage로 정상 전송 확인
INFO EXTRACT PUMP1, SHOWCH
```

### 17-3. Replicat 상태 확인

```
-- [GG] GGSCI에서 실행
STATUS REPLICAT REP1
LAG REPLICAT REP1

STATS REPLICAT REP1 TOTAL
-- Insert/Update/Delete 건수 증가 확인 (복제 중인 데이터 반영)

VIEW REPORT REP1
-- ABEND/ERROR 없음, Discard 없음 확인
```

### 17-4. Trail File 확인

```
-- [GG] GGSCI에서 실행
INFO EXTRACT EXT1, SHOWCH
-- Trail 파일 생성 및 용량 증가 확인
-- LOB 복제 시 Trail 급증 주의 (Object Storage 임계치 알람 설정 권장)
```

### 17-5. Discard 파일 확인

```
-- [GG] GGSCI에서 실행
VIEW DISCARD REP1
-- 기대값: 레코드 0건
-- Discard 있을 경우: 원인 분석 (중복 키, 참조 무결성 등)
```

### 17-6. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| EXT1 상태 RUNNING | | ☐ ✅ ☐ ❌ | |
| PUMP1 상태 RUNNING | | ☐ ✅ ☐ ❌ | |
| REP1 상태 RUNNING | | ☐ ✅ ☐ ❌ | |
| Discard 파일 레코드 0건 | | ☐ ✅ ☐ ⚠️ | |
| ABEND/ERROR 없음 (VIEW REPORT) | | ☐ ✅ ☐ ❌ | |
| Trail File 생성 및 증가 확인 | | ☐ ✅ ☐ ❌ | |
| STATS REPLICAT — 건수 증가 확인 | | ☐ ✅ ☐ ❌ | |

> **STEP 17 완료 서명**: __________________ 일시: __________________

---

## STEP 18. LAG 안정화 모니터링 (24h+)

**목적**: Extract/Replicat LAG이 30초 이하로 24시간 이상 지속적으로 유지되는지 모니터링
**담당**: OCI GG 담당자, 타겟 DBA
**예상 소요**: 24시간 이상 (연속 모니터링)
**실행 환경**: `[GG]`

---

### 18-1. LAG 모니터링 명령 (주기적 실행)

```
-- [GG] GGSCI에서 실행 (5~10분 간격)
LAG EXTRACT EXT1
LAG REPLICAT REP1

-- 또는 반복 실행
SEND EXTRACT EXT1, GETLAG
SEND REPLICAT REP1, GETLAG
```

### 18-2. OCI GG 콘솔 모니터링 설정

```
[OCI콘솔] GoldenGate → Deployments → Metrics
  - Extract LAG: 임계치 30초 알람 설정
  - Replicat LAG: 임계치 30초 알람 설정
  - 프로세스 ABEND: 즉시 알람 설정

[OCI콘솔] Monitoring → Alarms → Create Alarm
  - 메트릭 네임스페이스: oci_goldengate
  - 임계치: LAG > 30s → Notification 발송
```

### 18-3. LAG 안정화 기준 체크리스트

아래 모든 조건이 **24시간 연속** 유지되어야 Phase 6(검증)로 전환 가능

| 확인 시각 | EXT1 LAG | PUMP1 LAG | REP1 LAG | Discard 건수 | ABEND | 확인자 |
|---------|---------|----------|---------|------------|-------|--------|
| | | | | | | |
| | | | | | | |
| | | | | | | |
| | | | | | | |
| | | | | | | |

### 18-4. HANDLECOLLISIONS 제거 (LAG 안정화 후)

> **전제 조건**: Extract/Replicat LAG < 30초가 24시간 이상 유지된 후 수행

```
-- [GG] GGSCI에서 실행
STOP REPLICAT REP1
EDIT PARAMS REP1
-- HANDLECOLLISIONS 라인 제거 및 저장

START REPLICAT REP1
STATUS REPLICAT REP1
-- 기대값: RUNNING
```

> **이유**: HANDLECOLLISIONS는 초기 적재 충돌 처리용 — 완전 동기화 이후 존재 시 실제 데이터 충돌을 무시하는 문제 발생 가능

### 18-5. Phase 5 완료 체크리스트

| 항목 | 기대값 | 확인 결과 | 판정 | 확인자 |
|------|--------|-----------|------|--------|
| EXT1 상태 RUNNING (24h+) | RUNNING | | ☐ ✅ ☐ ❌ | |
| EXT1 LAG < 30초 (24h+) | < 30s | | ☐ ✅ ☐ ❌ | |
| PUMP1 상태 RUNNING (24h+) | RUNNING | | ☐ ✅ ☐ ❌ | |
| PUMP1 LAG < 30초 (24h+) | < 30s | | ☐ ✅ ☐ ❌ | |
| REP1 상태 RUNNING (24h+) | RUNNING | | ☐ ✅ ☐ ❌ | |
| REP1 LAG < 30초 (24h+) | < 30s | | ☐ ✅ ☐ ❌ | |
| Discard 파일 레코드 0건 (누적) | 0건 | | ☐ ✅ ☐ ❌ | |
| ABEND 이력 없음 | 0건 | | ☐ ✅ ☐ ❌ | |
| Trail File 용량 안정적 (급증 없음) | 정상 | | ☐ ✅ ☐ ❌ | |
| Heartbeat Table 정상 업데이트 | 정상 | | ☐ ✅ ☐ ❌ | |
| HANDLECOLLISIONS 제거 완료 | 제거됨 | | ☐ ✅ ☐ ❌ | |

**Phase 5 완료 승인**

| 역할 | 성명 | 서명 | 일시 |
|------|------|------|------|
| 마이그레이션 리더 | | | |
| OCI GG 담당자 | | | |
| 타겟 DBA | | | |

> **Phase 5 → Phase 6 전환 조건**: 위 체크리스트 전 항목 ✅ 완료
> → **다음 단계: `03.validation.md` 검증 단계 진행**

---

## 이슈 로그

| # | 발생 일시 | Phase/STEP | 이슈 내용 | 원인 분석 | 조치 내용 | 해결 일시 | 담당자 |
|---|---------|------------|-----------|-----------|-----------|---------|--------|
| 1 | | | | | | | |
| 2 | | | | | | | |
| 3 | | | | | | | |
| 4 | | | | | | | |
| 5 | | | | | | | |

---

## 긴급 연락처

| 상황 | 연락 대상 | 연락처 |
|------|-----------|--------|
| GG ABEND | OCI GG 담당자 | |
| RDS 접속 불가 | 소스 DBA / 인프라 담당 | |
| DBCS 접속 불가 | 타겟 DBA / OCI 인프라 | |
| 전체 롤백 결정 | 마이그레이션 리더 | |
