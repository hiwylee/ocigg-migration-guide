# AWS RDS (Oracle SE) → OCI DBCS (Oracle SE) 온라인 마이그레이션 계획

> **도구**: OCI GoldenGate Cloud + Oracle expdp/impdp
> **방식**: 온라인 마이그레이션 (서비스 중단 최소화)
> **검증 기준**: OCI_GG_Validation_Plan_20260313.xlsx (136 항목)
> **작성일**: 2026-03-17

---

## 목차
1. [마이그레이션 개요](#1-마이그레이션-개요)
2. [전체 단계 Overview](#2-전체-단계-overview)
3. [Phase 0: 사전 준비 및 환경 점검](#phase-0-사전-준비-및-환경-점검)
4. [Phase 1: 소스 DB 준비 (AWS RDS)](#phase-1-소스-db-준비-aws-rds)
5. [Phase 2: 타겟 DB 준비 (OCI DBCS)](#phase-2-타겟-db-준비-oci-dbcs)
6. [Phase 3: OCI GoldenGate 구성](#phase-3-oci-goldengate-구성)
7. [Phase 4: 초기 데이터 적재 (expdp/impdp)](#phase-4-초기-데이터-적재-expdpimpdp)
8. [Phase 5: 델타 동기화 (OCI GG 복제)](#phase-5-델타-동기화-oci-gg-복제)
9. [Phase 6: 검증 (Validation)](#phase-6-검증-validation)
10. [Phase 7: Cut-over](#phase-7-cut-over)
11. [Phase 8: Cut-over 후 안정화](#phase-8-cut-over-후-안정화)
12. [롤백 계획](#롤백-계획)
13. [Validation 체크리스트 요약](#validation-체크리스트-요약)

---

## 1. 마이그레이션 개요

| 항목 | 소스 | 타겟 |
|------|------|------|
| 클라우드 | AWS (Tokyo) | OCI (Tokyo) |
| DB 엔진 | Oracle SE (RDS) | Oracle SE (DBCS) |
| 복제 도구 | — | OCI GoldenGate Cloud |
| 초기 적재 | — | expdp / impdp |
| 예상 서비스 중단 | — | Cut-over 시 수십 분 이내 목표 |

### 마이그레이션 전략
```
[소스: AWS RDS Oracle SE]
        │
        │  ① expdp (SCN 고정 Full Export)
        ▼
[OCI Object Storage / S3]
        │
        │  ② impdp (Full Import → 타겟 스키마)
        ▼
[타겟: OCI DBCS Oracle SE]
        ▲
        │  ③ OCI GG Extract → Trail → Replicat (온라인 Delta 동기화)
        │     (expdp SCN 이후 변경분 지속 적용)
[소스: AWS RDS Oracle SE]
```

---

## 2. 전체 단계 Overview

| Phase | 단계명 | 주요 작업 | 예상 기간 |
|-------|--------|-----------|-----------|
| Phase 0 | 사전 준비 | 환경 점검, 네트워크, 계정 생성 | D-14 ~ D-7 |
| Phase 1 | 소스 DB 준비 | GG 파라미터, Supplemental Log 설정 | D-7 ~ D-5 |
| Phase 2 | 타겟 DB 준비 | DBCS 생성, 스키마 구조 이전 | D-7 ~ D-5 |
| Phase 3 | OCI GG 구성 | Deployment, Extract, Pump, Replicat | D-5 ~ D-3 |
| Phase 4 | 초기 적재 | expdp Export → impdp Import | D-3 ~ D-1 |
| Phase 5 | 델타 동기화 | SCN 기준 GG 복제 시작 및 안정화 | D-1 ~ D-Day |
| Phase 6 | 검증 | 136개 항목 전수 검증 | D-1 ~ D-Day |
| Phase 7 | Cut-over | 소스 서비스 중단 → 최종 동기화 | D-Day |
| Phase 8 | 안정화 | 모니터링, 이슈 처리, GG 종료 | D+1 ~ D+7 |

---

## Phase 0: 사전 준비 및 환경 점검

### 0-1. 인프라 확인

- [ ] OCI DBCS SE 인스턴스 스펙 결정 (소스 대비 동등 이상)
- [ ] OCI GoldenGate Deployment 생성 (Oracle 19c 지원 버전 확인)
- [ ] OCI Object Storage 버킷 생성 (Trail File 저장 + expdp dump 저장)
- [ ] AWS RDS → OCI 구간 네트워크 연결 확인
  - FastConnect 또는 Site-to-Site VPN 구성
  - RDS 보안그룹: OCI GG IP → TCP 1521 허용

### 0-2. 계정 준비

| 계정 | DB | 권한 | 용도 |
|------|----|------|------|
| GGADMIN | 소스 RDS | DBA_ROLE_PRIVS 필수 권한 | GG Extract |
| GGADMIN | 타겟 DBCS | DBA_ROLE_PRIVS 필수 권한 | GG Replicat |
| MIGRATION_USER | 소스 RDS | EXP_FULL_DATABASE | expdp |
| MIGRATION_USER | 타겟 DBCS | IMP_FULL_DATABASE | impdp |

**[검증 항목]** `01_GG_Process` #6: GGADMIN 계정 권한 확인
```sql
-- 소스/타겟 양쪽 실행
SELECT GRANTEE, GRANTED_ROLE FROM DBA_ROLE_PRIVS WHERE GRANTEE='GGADMIN';
SELECT GRANTEE, PRIVILEGE FROM DBA_SYS_PRIVS WHERE GRANTEE='GGADMIN';
```

### 0-3. 소스 DB 인벤토리 수집

```sql
-- 테이블 수
SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- LOB 컬럼 현황
SELECT OWNER, TABLE_NAME, COLUMN_NAME, SECUREFILE
FROM DBA_LOBS WHERE OWNER NOT IN ('SYS','SYSTEM');

-- 특수 객체 목록
SELECT OBJECT_TYPE, COUNT(*) FROM DBA_OBJECTS
WHERE STATUS='VALID' AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
GROUP BY OBJECT_TYPE ORDER BY 1;

-- DB 크기 확인
SELECT ROUND(SUM(BYTES)/1024/1024/1024,2) GB FROM DBA_SEGMENTS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

---

## Phase 1: 소스 DB 준비 (AWS RDS)

### 1-1. GoldenGate 관련 파라미터 설정

**[검증 #01_GG_Process #1]** ENABLE_GOLDENGATE_REPLICATION 활성화
```sql
-- SE는 기본 FALSE → 수동 설정 필수
EXEC rdsadmin.rdsadmin_util.set_configuration('enable_goldengate_replication','true');

-- 확인
SELECT VALUE FROM V$PARAMETER WHERE NAME='enable_goldengate_replication';
-- 기대값: TRUE
```

**[검증 #01_GG_Process #2]** Archive Log 모드 확인
```sql
SELECT LOG_MODE FROM V$DATABASE;
-- 기대값: ARCHIVELOG (RDS는 기본 ARCHIVELOG)
```

**[검증 #01_GG_Process #7]** RDS Redo Log 보존 기간 설정
```sql
-- 최소 24시간 이상 (Extract 장애 복구 대비)
EXEC rdsadmin.rdsadmin_util.set_configuration('archivelog retention hours', 24);
-- 권장: 48시간
```

**[검증 #01_GG_Process #5]** Redo Log 그룹/크기 확인
```sql
SELECT GROUP#, MEMBERS, BYTES/1024/1024 MB, STATUS FROM V$LOG;
-- 최소 3그룹, 그룹당 500MB 이상 권장
```

### 1-2. Supplemental Logging 설정

**[검증 #01_GG_Process #3]** 최소 Supplemental Logging 활성화
```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- 확인
SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;
-- 기대값: YES
```

**[검증 #01_GG_Process #4]** PK 없는 테이블 ALL COLUMNS 로깅 설정
```sql
-- PK 없는 테이블 식별
SELECT T.OWNER, T.TABLE_NAME
FROM DBA_TABLES T
WHERE T.OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
AND NOT EXISTS (
    SELECT 1 FROM DBA_CONSTRAINTS C
    WHERE C.OWNER=T.OWNER AND C.TABLE_NAME=T.TABLE_NAME
    AND C.CONSTRAINT_TYPE='P'
);

-- PK 없는 테이블에 ALL COLUMNS 로깅 적용
-- (대상 테이블별 실행)
ALTER TABLE <OWNER>.<TABLE_NAME> ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
```

### 1-3. Streams Pool 메모리 설정

**[검증 #05_Migration_Caution #3]**
```sql
-- SE는 Streams Pool 수동 설정 필요
-- RDS parameter group에서 streams_pool_size 설정 (최소 256MB)
-- AWS Console → RDS Parameter Group → streams_pool_size = 268435456 (256MB)
```

---

## Phase 2: 타겟 DB 준비 (OCI DBCS)

### 2-1. OCI DBCS 인스턴스 구성

- [ ] OCI DBCS SE 인스턴스 생성 (소스와 동일 Oracle 버전)
- [ ] NLS 파라미터 소스와 동일하게 설정

**[검증 #03_Data_Validation #21]** NLS_CHARACTERSET 일치 확인
```sql
-- 소스/타겟 양쪽 실행하여 비교
SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET',
                    'NLS_DATE_FORMAT','NLS_TIMESTAMP_FORMAT','NLS_TIMESTAMP_TZ_FORMAT');
-- 소스와 완전 일치 필수 (특히 NLS_CHARACTERSET: AL32UTF8 권장)
```

### 2-2. 스키마 구조 사전 이전 (DDL Only)

expdp/impdp CONTENT=METADATA_ONLY 로 스키마 구조 먼저 이전:
```bash
# 소스 RDS에서 메타데이터 Export
expdp MIGRATION_USER/password@RDS_TNS \
  FULL=Y \
  CONTENT=METADATA_ONLY \
  DUMPFILE=metadata_%U.dmp \
  LOGFILE=metadata_export.log \
  EXCLUDE=STATISTICS

# 타겟 DBCS에서 Import
impdp MIGRATION_USER/password@OCI_TNS \
  FULL=Y \
  CONTENT=METADATA_ONLY \
  DUMPFILE=metadata_%U.dmp \
  LOGFILE=metadata_import.log \
  TABLE_EXISTS_ACTION=SKIP
```

### 2-3. 타겟 스키마 구조 검증

**[검증 #02_Static_Schema #1~5]** 테이블 구조 비교
```sql
-- 소스와 타겟에서 각각 실행 후 비교
SELECT OWNER, TABLE_NAME, NUM_ROWS
FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME;

-- 컬럼 상세 비교
SELECT OWNER, TABLE_NAME, COLUMN_NAME, COLUMN_ID, DATA_TYPE,
       DATA_LENGTH, DATA_PRECISION, DATA_SCALE, NULLABLE, DATA_DEFAULT
FROM DBA_TAB_COLUMNS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME, COLUMN_ID;
```

**[검증 #02_Static_Schema #6~9]** 인덱스 검증
```sql
-- BITMAP Index SE 미지원 확인 (소스에 있으면 타겟에서 일반 Index로 대체 필요)
SELECT OWNER, TABLE_NAME, INDEX_NAME, INDEX_TYPE
FROM DBA_INDEXES
WHERE INDEX_TYPE = 'BITMAP'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**[검증 #02_Static_Schema #37~38]** INVALID 객체 점검
```sql
-- INVALID 객체 조회
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- 재컴파일
EXEC DBMS_UTILITY.COMPILE_SCHEMA(schema => '<SCHEMA_NAME>', compile_all => FALSE);
```

### 2-4. 특수 객체 타겟 준비

**[검증 #04_Special_Objects - Trigger]** Replicat 중 Trigger 비활성화 준비
```sql
-- 타겟의 모든 Trigger 비활성화 스크립트 생성
SELECT 'ALTER TRIGGER '||OWNER||'.'||TRIGGER_NAME||' DISABLE;'
FROM DBA_TRIGGERS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**[검증 #04_Special_Objects - MV]** MV 재생성 준비
```sql
-- 소스 MV 목록 및 REFRESH 방식 파악
SELECT OWNER, MVIEW_NAME, REFRESH_METHOD, REFRESH_MODE, STALENESS
FROM DBA_MVIEWS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**[검증 #04_Special_Objects - DB Link]** DB Link 타겟 환경 맞게 수정
```sql
-- 소스 DB Link 목록
SELECT OWNER, DB_LINK, USERNAME, HOST FROM DBA_DB_LINKS;
-- 타겟에서 네트워크 주소를 OCI 환경에 맞게 수정하여 재생성
```

**[검증 #04_Special_Objects - DBMS_JOB]** DBMS_JOB → DBMS_SCHEDULER 전환
```sql
-- 소스 DBMS_JOB 목록
SELECT JOB, WHAT, INTERVAL, BROKEN, NEXT_DATE FROM DBA_JOBS;
-- 타겟에서 DBMS_SCHEDULER로 재작성 (SE 19c에서 DBMS_JOB Deprecated)
```

---

## Phase 3: OCI GoldenGate 구성

### 3-1. OCI GG Deployment 확인

**[검증 #01_GG_Process #8]** OCI GG 버전 확인
- OCI Console → GoldenGate → Deployments
- Oracle 19c SE 지원 버전 확인 (21c 이상 권장)
- 자동 업데이트 정책 검토

### 3-2. Connection 설정

```
# OCI GG Console에서 Connection 생성
1. Source Connection:
   - Type: Oracle Database
   - Host: <RDS Endpoint>
   - Port: 1521
   - Service Name: <RDS_SERVICE_NAME>
   - Username: GGADMIN
   - Password: <password>

2. Target Connection:
   - Type: Oracle Database
   - Host: <OCI DBCS Private IP>
   - Port: 1521
   - Service Name: <DBCS_SERVICE_NAME>
   - Username: GGADMIN
   - Password: <password>
```

**[검증 #01_GG_Process #9]** 네트워크 연결 확인
```bash
# OCI GG Deployment에서 소스 RDS 1521 포트 접근 가능 여부
telnet <RDS_ENDPOINT> 1521
```

### 3-3. Extract 프로세스 구성

```
-- OCI GG Admin Server에서 실행
ADD CREDENTIALSTORE
ALTER CREDENTIALSTORE ADD USER ggadmin@source_db ALIAS ggadmin_src

-- Extract 생성 (Initial Load 완료 후 SCN 지정하여 시작)
ADD EXTRACT EXT1, INTEGRATED TRANLOG, BEGIN NOW
ADD EXTTRAIL ./dirdat/aa, EXTRACT EXT1

-- Extract 파라미터 설정
EDIT PARAMS EXT1
-- 파라미터 내용:
EXTRACT EXT1
USERIDALIAS ggadmin_src
EXTTRAIL ./dirdat/aa
SEQUENCE <SCHEMA>.*;
TABLE <SCHEMA>.*;
SOURCETIMEZONE <SOURCE_TZ>;
-- DDL 복제 설정 (SE 제약 범위 내에서만)
DDL INCLUDE MAPPED OBJTYPE 'TABLE'
```

**[검증 #04_Special_Objects - DDL Replication #39]** DDL 복제 대상 범위 설정 확인
- SE에서 미지원 DDL 유형 사전 파악
- 지원 외 DDL 발생 시 수동 처리 절차 수립

### 3-4. Data Pump (Trail Pump) 프로세스 구성

```
ADD EXTRACT PUMP1, EXTTRAILSOURCE ./dirdat/aa
ADD RMTTRAIL <OCI_OBJECT_STORAGE_PATH>/rt, EXTRACT PUMP1

EDIT PARAMS PUMP1
-- 파라미터:
EXTRACT PUMP1
USERIDALIAS ggadmin_src
RMTTRAIL <OCI_OBJECT_STORAGE_PATH>/rt
PASSTHRU
TABLE <SCHEMA>.*;
```

**[검증 #01_GG_Process #17]** OCI Object Storage 연결 확인
```
-- OCI GG Console에서 Trail Storage 설정 확인
-- Object Storage 버킷 접근 권한 및 연결 상태 확인
```

### 3-5. Replicat 프로세스 구성

```
ADD REPLICAT REP1, INTEGRATED, EXTTRAIL <OCI_OBJECT_STORAGE_PATH>/rt

EDIT PARAMS REP1
-- 파라미터:
REPLICAT REP1
USERIDALIAS ggadmin_tgt
ASSUMETARGETDEFS
MAP <SCHEMA>.*, TARGET <SCHEMA>.*;
-- Trigger 이중 실행 방지
SUPPRESSTRIGGERS
-- Sequence 복제 설정
SEQUENCE <SCHEMA>.*;
HANDLECOLLISIONS  -- 초기 적재 중 충돌 처리 (동기화 완료 후 제거)
```

**[검증 #01_GG_Process #22]** SUPPRESSTRIGGERS 설정 확인

---

## Phase 4: 초기 데이터 적재 (expdp/impdp)

### 4-1. SCN 고정 및 Export

```bash
# 1. Extract 시작 SCN 확인 및 기록
sqlplus -S system/password@RDS_TNS <<'EOF'
SELECT CURRENT_SCN FROM V$DATABASE;
EOF
# → SCN 값 기록 (예: 12345678)

# 2. Consistent Export (SCN 고정)
expdp MIGRATION_USER/password@RDS_TNS \
  FULL=Y \
  CONTENT=DATA_ONLY \
  FLASHBACK_SCN=12345678 \
  DUMPFILE=fulldata_%U.dmp \
  FILESIZE=10G \
  PARALLEL=4 \
  LOGFILE=fulldata_export.log \
  EXCLUDE=STATISTICS,INDEX,CONSTRAINT,REF_CONSTRAINT

# 3. Dump 파일을 OCI Object Storage로 전송
oci os object bulk-upload \
  --bucket-name <BUCKET_NAME> \
  --src-dir /backup/dump/ \
  --prefix migration/
```

### 4-2. 타겟 Import

```bash
# OCI DBCS에서 실행
# Object Storage에서 Dump 파일 다운로드
oci os object bulk-download \
  --bucket-name <BUCKET_NAME> \
  --download-dir /backup/dump/ \
  --prefix migration/

# impdp 실행 (데이터만, 구조는 이미 이전 완료)
impdp MIGRATION_USER/password@OCI_TNS \
  FULL=Y \
  CONTENT=DATA_ONLY \
  DUMPFILE=fulldata_%U.dmp \
  PARALLEL=4 \
  LOGFILE=fulldata_import.log \
  TABLE_EXISTS_ACTION=TRUNCATE
```

### 4-3. Import 완료 후 점검

**[검증 #03_Data_Validation #1]** Row Count 초기 확인
```sql
-- 소스와 타겟에서 각각 실행 후 비교 (SCN 기준 시점의 카운트)
SELECT OWNER, TABLE_NAME, NUM_ROWS
FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME;
-- (GATHER STATS 후 정확한 비교 가능)
```

---

## Phase 5: 델타 동기화 (OCI GG 복제)

### 5-1. GG 복제 시작

```
-- Extract를 SCN 기준점부터 시작
START EXTRACT EXT1, AFTERCSN 12345678

-- Pump 시작
START EXTRACT PUMP1

-- Replicat 시작 (HANDLECOLLISIONS 활성화 상태)
START REPLICAT REP1
```

### 5-2. GG 프로세스 상태 모니터링

**[검증 #01_GG_Process #10~14]** Extract 상태 확인
```
-- OCI GG Admin Server GGSCI
STATUS EXTRACT EXT1
LAG EXTRACT EXT1
INFO EXTRACT EXT1, DETAIL
VIEW REPORT EXT1
-- 기대값: STATUS=RUNNING, LAG < 30초, ABEND 없음
```

**[검증 #01_GG_Process #15~17]** Pump 상태 확인
```
STATUS EXTRACT PUMP1
LAG EXTRACT PUMP1
-- 기대값: STATUS=RUNNING, LAG < 30초
```

**[검증 #01_GG_Process #18~23]** Replicat 상태 확인
```
STATUS REPLICAT REP1
LAG REPLICAT REP1
STATS REPLICAT REP1 TOTAL
-- Discard 파일 확인
VIEW REPORT REP1
-- 기대값: STATUS=RUNNING, LAG < 30초, Discard=0건
```

### 5-3. LAG 안정화 확인

- [ ] Extract LAG < 30초 지속 유지 (최소 24시간 모니터링)
- [ ] Replicat LAG < 30초 지속 유지
- [ ] Discard 파일 레코드 0건 유지
- [ ] Trail File 용량 정상 범위 내 유지

**[검증 #01_GG_Process #24~25]** Trail File 모니터링
```
INFO EXTRACT EXT1, SHOWCH
-- Trail 파일 용량 확인 (LOB 복제 시 급증 주의)
```

---

## Phase 6: 검증 (Validation)

> GG 복제가 안정화된 후 (LAG < 30초, 24시간 유지 확인 후) 전수 검증 수행

### 6-1. GG 프로세스 검증 (01_GG_Process - 28항목)

| 검증 영역 | 항목 수 | 핵심 확인 사항 |
|-----------|---------|---------------|
| Pre-Check | 9개 | 파라미터, Archive Log, Supplemental Log, GGADMIN 권한 |
| Extract | 5개 | 상태 RUNNING, LAG < 30초, ABEND 없음 |
| Data Pump | 3개 | 상태 RUNNING, LAG < 30초, Object Storage 연결 |
| Replicat | 6개 | 상태 RUNNING, LAG < 30초, Stats, Discard 0건, SUPPRESSTRIGGERS |
| Trail File | 2개 | 용량 모니터링, 보존 정책 |
| 상시운영 | 3개 | LAG 알람, 비밀번호 만료, 자동 패치 |

### 6-2. 정적 구조 검증 (02_Static_Schema - 38항목)

**테이블 구조 비교 쿼리**
```sql
-- 소스/타겟 테이블 수 비교
SELECT COUNT(*) FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- 컬럼 구조 차이 확인 (소스와 타겟에서 각각 실행 후 Minus)
SELECT OWNER, TABLE_NAME, COLUMN_NAME, DATA_TYPE, DATA_LENGTH,
       DATA_PRECISION, DATA_SCALE, NULLABLE, COLUMN_ID
FROM DBA_TAB_COLUMNS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME, COLUMN_ID;
```

**제약조건 비교**
```sql
-- PK/FK/UNIQUE/CHECK 제약 상태 확인
SELECT OWNER, TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE, STATUS
FROM DBA_CONSTRAINTS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
AND CONSTRAINT_TYPE IN ('P','R','U','C')
ORDER BY OWNER, TABLE_NAME, CONSTRAINT_TYPE;

-- DISABLED 제약 없음 확인
SELECT OWNER, TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM DBA_CONSTRAINTS
WHERE STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- 기대값: 0건
```

**시퀀스 검증**
```sql
-- 시퀀스 속성 비교
SELECT SEQUENCE_OWNER, SEQUENCE_NAME, INCREMENT_BY, MIN_VALUE, MAX_VALUE,
       CACHE_SIZE, LAST_NUMBER
FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY SEQUENCE_OWNER, SEQUENCE_NAME;
-- 타겟 LAST_NUMBER ≥ 소스 MAX 확인 (CACHE로 인한 Gap 필수 확인)
```

**INVALID 객체 0건 확인**
```sql
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- 기대값: 0건 (있으면 즉시 재컴파일)
```

**사용자/권한 비교**
```sql
-- 사용자 목록 (시스템 계정 제외)
SELECT USERNAME, ACCOUNT_STATUS, DEFAULT_TABLESPACE FROM DBA_USERS
WHERE USERNAME NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS',
                       'AUDSYS','CTXSYS','DBSFWUSER','DBSNMP','DVSYS',
                       'GGSYS','GSMADMIN_INTERNAL','GSMCATUSER','GSMUSER',
                       'LBACSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
                       'ORDPLUGINS','ORDSYS','REMOTE_SCHEDULER_AGENT',
                       'SI_INFORMTN_SCHEMA','SYS$UMF','SYSBACKUP','SYSDG',
                       'SYSKM','SYSRAC','WMSYS','XDB','XS$NULL');
```

### 6-3. 데이터 정합성 검증 (03_Data_Validation - 25항목)

**Row Count 비교**
```sql
-- 동적 SQL로 전체 테이블 Row Count 비교
-- 소스와 타겟에서 각각 실행하여 비교
SELECT OWNER, TABLE_NAME,
       TO_NUMBER(EXTRACTVALUE(XMLTYPE(DBMS_XMLGEN.GETXML(
         'SELECT COUNT(*) C FROM '||OWNER||'.'||TABLE_NAME)),
         '/ROWSET/ROW/C')) AS ROW_COUNT
FROM DBA_TABLES
WHERE OWNER = '<TARGET_SCHEMA>'
ORDER BY TABLE_NAME;
```

**ORA_HASH 체크섬 비교**
```sql
-- 핵심 테이블 대상 Checksum 비교 (소스/타겟 동일 쿼리 실행)
SELECT SUM(ORA_HASH(ROWID)) AS CHECKSUM, COUNT(*) AS CNT
FROM <SCHEMA>.<TABLE_NAME>;
```

**LOB 검증**
```sql
-- LOB 컬럼 크기 비교
SELECT T.TABLE_NAME, L.COLUMN_NAME,
       SUM(DBMS_LOB.GETLENGTH(T.<LOB_COL>)) AS TOTAL_SIZE,
       COUNT(*) AS CNT
FROM <SCHEMA>.<TABLE_NAME> T, DBA_LOBS L
WHERE L.OWNER='<SCHEMA>' AND L.TABLE_NAME='<TABLE_NAME>'
GROUP BY T.TABLE_NAME, L.COLUMN_NAME;
```

**NLS 및 문자셋 검증**
```sql
-- NLS 설정 비교
SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET',
                    'NLS_DATE_FORMAT','NLS_TIMESTAMP_TZ_FORMAT',
                    'NLS_LANGUAGE','NLS_TERRITORY','NLS_SORT');

-- 한글 데이터 샘플 확인
SELECT <KOREAN_COLUMN> FROM <SCHEMA>.<TABLE_NAME> WHERE ROWNUM <= 10;
```

**참조 무결성 확인**
```sql
-- Orphan Row 확인
SELECT COUNT(*) FROM <CHILD_TABLE> C
WHERE NOT EXISTS (
    SELECT 1 FROM <PARENT_TABLE> P
    WHERE P.<PK_COL> = C.<FK_COL>
);
-- 기대값: 0건
```

### 6-4. 특수 객체 검증 (04_Special_Objects - 42항목)

**MV 검증**
```sql
-- MV Row Count 비교
SELECT OWNER, MVIEW_NAME, STALENESS FROM DBA_MVIEWS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- 타겟 MV REFRESH 테스트
EXEC DBMS_MVIEW.REFRESH('<SCHEMA>.<MV_NAME>','C');
```

**Trigger 재활성화 확인** (Cut-over 후)
```sql
-- 타겟 Trigger 상태 확인
SELECT OWNER, TRIGGER_NAME, STATUS FROM DBA_TRIGGERS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**Sequence Gap 확인**
```sql
-- 타겟 Sequence > 소스 Sequence MAX 확인
-- 소스에서:
SELECT SEQUENCE_NAME, LAST_NUMBER FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER='<SCHEMA>';

-- 타겟에서:
SELECT SEQUENCE_NAME, LAST_NUMBER FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER='<SCHEMA>';
-- 타겟 LAST_NUMBER ≥ 소스 LAST_NUMBER + CACHE_SIZE
```

**DBMS_JOB → DBMS_SCHEDULER 전환 확인**
```sql
-- 소스 JOB 확인
SELECT JOB, WHAT, INTERVAL, BROKEN FROM DBA_JOBS;

-- 타겟 SCHEDULER JOB 확인
SELECT JOB_NAME, STATUS, LAST_RUN_DURATION, NEXT_RUN_DATE
FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

### 6-5. 마이그레이션 주의사항 체크 (05_Migration_Caution - 26항목)

| 구분 | 핵심 확인 항목 | 중요도 |
|------|--------------|--------|
| SE 제약 | ENABLE_GOLDENGATE_REPLICATION=TRUE | 상 |
| SE 제약 | PK 없는 테이블 ALL COLUMNS Supplemental Log | 상 |
| SE 제약 | Streams Pool 메모리 설정 | 중 |
| SE 제약 | DDL Replication 미지원 유형 식별 | 상 |
| SE 제약 | BITMAP Index → 일반 Index 대체 | 중 |
| OCI GG | RDS Redo Log 보존 24h 이상 | 상 |
| OCI GG | Cloud 버전 DDL 제약 확인 | 상 |
| OCI GG | MV 수동 재생성 | 상 |
| OCI GG | DB Link 수동 재생성 | 상 |
| Cut-over | SCN 기반 동기화 | 상 |
| Cut-over | Sequence 재설정 | 상 |
| Cut-over | Trigger/FK 재활성화 | 상 |

---

## Phase 7: Cut-over

> **전제 조건**: Phase 6 검증 전체 PASS 또는 허용된 WARN 수준

### 7-1. Cut-over 사전 체크리스트

- [ ] GG 복제 LAG < 5초 (이상적: 0초)
- [ ] Discard 파일 레코드 0건
- [ ] 검증 136개 항목 PASS (또는 WARN 원인 분석 완료)
- [ ] 롤백 절차 확인 완료
- [ ] 관련 팀 (앱, DBA, 인프라) Cut-over 알림 완료
- [ ] 유지보수 공지 완료

### 7-2. Cut-over 실행 순서

```
1. 소스 DB 애플리케이션 세션 종료 (앱 서버 다운 또는 연결 차단)

2. 소스 DB CURRENT_SCN 기록
   SELECT CURRENT_SCN FROM V$DATABASE;  -- 최종 SCN 기록

3. GG LAG = 0 확인 대기
   LAG EXTRACT EXT1
   LAG REPLICAT REP1
   -- LAG=0이 될 때까지 대기 (타임아웃: 30분)

4. Replicat 중지
   STOP REPLICAT REP1

5. HANDLECOLLISIONS 제거 (Replicat 재기동 시)
   EDIT PARAMS REP1  -- HANDLECOLLISIONS 라인 제거
   START REPLICAT REP1

6. 타겟 DB 최종 검증 (Row Count, 최신 데이터 확인)

7. Cut-over 완료 처리:
   a) SUPPRESSTRIGGERS → 타겟 Trigger ENABLE
   b) FK Constraint 일괄 ENABLE
   c) DBMS_SCHEDULER JOB ENABLE 및 NEXT_RUN_DATE 재설정
   d) DB Link 연결 전환 테스트
   e) Sequence 최종값 재설정
      ALTER SEQUENCE <SCHEMA>.<SEQ_NAME> INCREMENT BY <GAP>;
      SELECT <SCHEMA>.<SEQ_NAME>.NEXTVAL FROM DUAL;
      ALTER SEQUENCE <SCHEMA>.<SEQ_NAME> INCREMENT BY 1;

8. 애플리케이션 DNS/연결 문자열 타겟 DB로 전환

9. 애플리케이션 기동 및 정상 동작 확인

10. GG Extract/Pump 중지 (동기화 완전 종료)
    STOP EXTRACT EXT1
    STOP EXTRACT PUMP1
```

**[검증 #05_Migration_Caution #14~19]** Cut-over 체크리스트

### 7-3. Cut-over 후 즉시 검증

```sql
-- 1. 최신 데이터 확인
SELECT MAX(CREATED_DATE) FROM <SCHEMA>.<KEY_TABLE>;

-- 2. Sequence 현재값 확인
SELECT LAST_NUMBER FROM DBA_SEQUENCES WHERE SEQUENCE_OWNER='<SCHEMA>';

-- 3. Trigger 활성화 확인
SELECT COUNT(*) FROM DBA_TRIGGERS
WHERE STATUS='DISABLED' AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- 기대값: 0건

-- 4. FK 활성화 확인
SELECT COUNT(*) FROM DBA_CONSTRAINTS
WHERE STATUS='DISABLED' AND CONSTRAINT_TYPE='R'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- 기대값: 0건
```

---

## Phase 8: Cut-over 후 안정화

### 8-1. 상시 운영 모니터링 설정

**[검증 #01_GG_Process #26~28]** 모니터링 알람 설정
- OCI GG Console → Monitoring → LAG Alert 30초 이하 설정
- OCI Monitoring → Alarm 생성 (Extract/Replicat 상태 이상 시)

### 8-2. 상시 운영 Top 10 주의사항 (06_Result_Dashboard)

| 순위 | 항목 | 조치 |
|------|------|------|
| 1 | Extract/Replicat LAG 상시 모니터링 | LAG > 30초 알람 설정 |
| 2 | PK 없는 테이블 ALL COLUMNS Logging | 신규 테이블 생성 시 즉시 적용 |
| 3 | Sequence GAP 누적 관리 | 정기적 Gap 확인 |
| 4 | Trigger 이중 실행 방지 | GGADMIN 세션 Trigger 예외 로직 확인 |
| 5 | DDL Replication ABEND 관리 | 미지원 DDL 수동 처리 절차 |
| 6 | RDS Redo Log 보존 기간 관리 | 최소 24h 이상 유지 |
| 7 | GGADMIN 비밀번호 만료 모니터링 | 만료 전 갱신 절차 |
| 8 | LOB 컬럼 Trail File 용량 급증 | Object Storage 임계치 알람 |
| 9 | Constraint DISABLED 상태 정기 점검 | 주간 점검 |
| 10 | NLS 파라미터/타임존 변경 금지 | 변경 금지 정책 수립 |

### 8-3. 소스 DB 유지 기간

- Cut-over 후 최소 2주간 소스 RDS 유지 (롤백 대비)
- 이상 없음 확인 후 RDS 종료 및 비용 절감

---

## 롤백 계획

### 롤백 트리거 조건
- Cut-over 후 애플리케이션 심각한 오류 발생
- 데이터 무결성 문제 발견
- 타겟 DB 성능 임계치 초과 (소스 대비 30% 이상 저하)

### 롤백 절차

```
1. 타겟 DB 애플리케이션 세션 즉시 차단
2. 소스 RDS ENABLE_GOLDENGATE_REPLICATION 유지 상태 확인
3. 역방향 GG 복제 검토 (타겟→소스, 필요시)
   - 단, Cut-over 이후 소스에 발생한 변경이 없으면 소스 그대로 사용 가능
4. 애플리케이션 연결을 소스 RDS로 복원
5. 원인 분석 및 재마이그레이션 일정 수립
```

---

## Validation 체크리스트 요약

> 검증 결과는 OCI_GG_Validation_Plan_20260313.xlsx 의 결과 컬럼에 기록

| Sheet | 영역 | 총 항목 | [상] 항목 | 비고 |
|-------|------|---------|-----------|------|
| 01_GG_Process | GG 프로세스 | 28 | 18 | Pre-Check/Extract/Replicat |
| 02_Static_Schema | 정적 구조 | 38 | 17 | 테이블/인덱스/제약/시퀀스 |
| 03_Data_Validation | 데이터 정합성 | 25 | 13 | Row Count/Checksum/LOB/NLS |
| 04_Special_Objects | 특수 객체 | 42 | 21 | MV/Trigger/DBLink/JOB/파티션 |
| 05_Migration_Caution | 주의사항 | 26 | 16 | SE제약/OCI GG/Cut-over |
| **합계** | | **159** | **85** | |

### Go/No-Go 기준

| 기준 | 조건 |
|------|------|
| **Go (진행)** | 중요도 [상] 항목 전체 PASS + WARN 항목 원인 분석 완료 |
| **Conditional Go** | WARN 항목 존재하나 비즈니스 영향 없음 확인 + 조치 계획 수립 |
| **No-Go (중단)** | 중요도 [상] 항목 중 1건 이상 FAIL |

---

*작성: 마이그레이션 팀 | 검토: TBD | 승인: TBD*
