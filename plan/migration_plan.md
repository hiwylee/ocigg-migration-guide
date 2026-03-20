# AWS RDS (Oracle SE) → OCI DBCS (Oracle SE) 온라인 마이그레이션 계획

> **소스**: AWS RDS Oracle SE (Tokyo)
> **타겟**: OCI DBCS Oracle SE (Tokyo)
> **도구**: OCI GoldenGate Cloud + Oracle expdp / impdp
> **방식**: 온라인 마이그레이션 (서비스 중단 최소화 — Cut-over 수십 분 이내 목표)
> **검증 기준**: OCI_GG_Validation_Plan_20260313.xlsx (6개 시트, 136개 항목)
> **작성일**: 2026-03-17 | 버전: v1.0

---

## 목차

1. [마이그레이션 개요 및 전략](#1-마이그레이션-개요-및-전략)
2. [전체 단계 Overview](#2-전체-단계-overview)
3. [Phase 0: 사전 준비 및 환경 점검](#phase-0-사전-준비-및-환경-점검)
4. [Phase 1: 소스 DB 준비 (AWS RDS)](#phase-1-소스-db-준비-aws-rds)
5. [Phase 2: 타겟 DB 준비 (OCI DBCS)](#phase-2-타겟-db-준비-oci-dbcs)
6. [Phase 3: OCI GoldenGate 구성](#phase-3-oci-goldengate-구성)
7. [Phase 4: 초기 데이터 적재 (expdp / impdp)](#phase-4-초기-데이터-적재-expdp--impdp)
8. [Phase 5: 델타 동기화 (OCI GG 복제)](#phase-5-델타-동기화-oci-gg-복제)
9. [Phase 6: 검증 (Validation)](#phase-6-검증-validation)
10. [Phase 7: Cut-over](#phase-7-cut-over)
11. [Phase 8: Cut-over 후 안정화](#phase-8-cut-over-후-안정화)
12. [롤백 계획](#롤백-계획)
13. [Validation 체크리스트 요약 (136항목)](#validation-체크리스트-요약-136항목)

---

## 1. 마이그레이션 개요 및 전략

### 환경 구성

| 항목 | 소스 | 타겟 |
|------|------|------|
| 클라우드 | AWS (Tokyo ap-northeast-1) | OCI (Tokyo ap-tokyo-1) |
| DB 엔진 | Oracle SE (RDS) | Oracle SE (DBCS) |
| 복제 도구 | — | OCI GoldenGate Cloud |
| 초기 적재 | — | expdp / impdp |
| 서비스 중단 목표 | — | Cut-over 시 30분 이내 |

### 마이그레이션 아키텍처

```
[소스: AWS RDS Oracle SE]
         │
         │  ① expdp — SCN 고정 Full Export (DATA_ONLY)
         │             ※ Phase 2에서 METADATA_ONLY 먼저 이전
         ▼
[OCI Object Storage 버킷]
         │
         │  ② impdp — Full Import (DATA_ONLY)
         ▼
[타겟: OCI DBCS Oracle SE]
         ▲
         │  ③ OCI GG Extract → Pump → Trail → Replicat
         │     (expdp SCN 이후 변경분 지속 적용)
         │
[소스: AWS RDS Oracle SE]
```

### 핵심 원칙

- **SCN 기반 연속성**: expdp FLASHBACK_SCN으로 특정 시점을 고정하고, 해당 SCN 이후 변경분을 GG가 캐치업
- **SE 제약 최우선 반영**: `ENABLE_GOLDENGATE_REPLICATION`, Supplemental Logging, Streams Pool 등 SE 전용 수동 설정 필수
- **검증 우선**: 136개 항목 모두 PASS 또는 WARN 원인 분석 완료 후에만 Cut-over 진행
- **무중단 롤백 준비**: Cut-over 후 2주간 소스 RDS 유지, 역방향 GG 사전 준비 검토
- **전체 DB 이전 범위**: 시스템 내장 스키마를 제외한 모든 사용자 스키마 대상 (특정 애플리케이션 스키마 단위가 아님)

### 시스템 스키마 제외 목록 (전 계획서 공통 기준)

> 아래 목록은 expdp/impdp EXCLUDE, GG TABLE EXCLUDE, 검증 쿼리 WHERE 조건에 **공통 적용**되는 기준입니다.

```sql
-- ■ 시스템 내장 스키마 (마이그레이션 제외 대상)
-- 이 목록을 EXCLUDE_SYSTEM_SCHEMAS 로 정의하여 모든 쿼리/설정에 일관 적용
'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER',
'GSMUSER','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
'ORDPLUGINS','ORDSYS','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA',
'SYS$UMF','SYSBACKUP','SYSDG','SYSKM','SYSRAC','WMSYS','XDB','XS$NULL',
-- GoldenGate 자체 스키마 (복제 제외 필수)
'GGADMIN','GGS_TEMP'
```

```sql
-- ■ 마이그레이션 대상 사용자 스키마 확인 (위 목록 제외 후 전체)
SELECT USERNAME FROM DBA_USERS
WHERE USERNAME NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER',
    'GSMUSER','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
    'ORDPLUGINS','ORDSYS','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA',
    'SYS$UMF','SYSBACKUP','SYSDG','SYSKM','SYSRAC','WMSYS','XDB','XS$NULL',
    'GGADMIN','GGS_TEMP','MIGRATION_USER'
)
ORDER BY USERNAME;
-- → 이 목록이 실제 GG TABLE 파라미터와 통계/컴파일 대상 범위가 됨
```

---

## 2. 전체 단계 Overview

| Phase | 단계명 | 주요 작업 | 기간 |
|-------|--------|-----------|------|
| Phase 0 | 사전 준비 | 인벤토리, 네트워크, 계정, 도구 확인 | D-14 ~ D-10 |
| Phase 1 | 소스 DB 준비 | GG 파라미터, Supplemental Log, RDS 설정 | D-10 ~ D-7 |
| Phase 2 | 타겟 DB 준비 | DBCS 생성, 스키마 구조(DDL) 이전, 특수 객체 준비 | D-10 ~ D-7 |
| **Dry Run** | 리허설 | 비업무 시간에 전체 절차 시뮬레이션 | D-7 |
| Phase 3 | OCI GG 구성 | Deployment, Connection, Extract/Pump/Replicat | D-7 ~ D-5 |
| Phase 4 | 초기 적재 | expdp Export → 전송 → impdp Import | D-5 ~ D-2 |
| Phase 5 | 델타 동기화 | SCN 기준 GG 복제 시작 및 안정화 (24h+) | D-2 ~ D-Day |
| Phase 6 | 검증 | 136개 항목 전수 검증, Go/No-Go 판정 | D-1 ~ D-Day |
| Phase 7 | Cut-over | 소스 차단 → LAG=0 → 전환 완료 | D-Day |
| Phase 8 | 안정화 | 모니터링, 이슈 처리, GG 종료 계획 | D+1 ~ D+14 |

---

## Phase 0: 사전 준비 및 환경 점검

### 0-1. 소스 DB 인벤토리 수집

```sql
-- DB 크기 및 스키마 현황
SELECT OWNER,
       ROUND(SUM(BYTES)/1024/1024/1024, 2) AS GB
FROM DBA_SEGMENTS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
GROUP BY OWNER
ORDER BY 2 DESC;

-- 객체 유형별 수량
SELECT OBJECT_TYPE, COUNT(*)
FROM DBA_OBJECTS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
GROUP BY OBJECT_TYPE
ORDER BY 1;

-- PK 없는 테이블 (Supplemental Log 추가 필요)
SELECT T.OWNER, T.TABLE_NAME
FROM DBA_TABLES T
WHERE T.OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
AND NOT EXISTS (
    SELECT 1 FROM DBA_CONSTRAINTS C
    WHERE C.OWNER = T.OWNER
    AND C.TABLE_NAME = T.TABLE_NAME
    AND C.CONSTRAINT_TYPE = 'P'
);

-- LOB 컬럼 현황 (BasicFile/SecureFile 구분)
SELECT OWNER, TABLE_NAME, COLUMN_NAME, SECUREFILE
FROM DBA_LOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- XMLTYPE 컬럼 보유 테이블
SELECT OWNER, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM DBA_TAB_COLUMNS
WHERE DATA_TYPE IN ('XMLTYPE', 'SYS.XMLTYPE')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- 파티션 테이블 현황
SELECT OWNER, TABLE_NAME, PARTITIONING_TYPE, SUBPARTITIONING_TYPE, PARTITION_COUNT
FROM DBA_PART_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- Directory Object
SELECT OWNER, DIRECTORY_NAME, DIRECTORY_PATH FROM DBA_DIRECTORIES ORDER BY 2;

-- External Table
SELECT OWNER, TABLE_NAME, DEFAULT_DIRECTORY_NAME, ACCESS_TYPE
FROM DBA_EXTERNAL_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- MV 목록
SELECT OWNER, MVIEW_NAME, REFRESH_METHOD, REFRESH_MODE, STALENESS
FROM DBA_MVIEWS WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- DB Link 목록
SELECT OWNER, DB_LINK, USERNAME, HOST FROM DBA_DB_LINKS;

-- DBMS_JOB 목록
SELECT JOB, WHAT, INTERVAL, BROKEN, NEXT_DATE FROM DBA_JOBS;

-- TIMESTAMP WITH TIME ZONE 컬럼
SELECT OWNER, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM DBA_TAB_COLUMNS
WHERE DATA_TYPE IN ('TIMESTAMP WITH TIME ZONE','TIMESTAMP WITH LOCAL TIME ZONE')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

### 0-2. 인프라 준비

- [ ] OCI DBCS SE 인스턴스 생성 (소스 대비 동등 이상 스펙)
- [ ] OCI GoldenGate Deployment 생성
  - Oracle 19c 지원 버전 확인 (`01_GG_Process #8`)
  - 자동 업데이트 정책 검토 (`01_GG_Process #28`)
- [ ] OCI Object Storage 버킷 생성
  - Trail File 저장 버킷 (GG용)
  - Dump File 저장 버킷 (expdp/impdp용)
  - 보존 기간 정책 설정 (`01_GG_Process #25`)
- [ ] 네트워크 연결 구성 (`01_GG_Process #9`)
  - AWS RDS → OCI GG 구간: Site-to-Site VPN 또는 전용선
  - RDS 보안그룹: OCI GG Deployment IP → TCP 1521 허용
  - OCI DBCS NSG: OCI GG → TCP 1521 허용

### 0-3. 계정 준비

| 계정 | DB | 필요 권한 | 용도 |
|------|----|-----------|------|
| GGADMIN | 소스 RDS | CREATE SESSION, ALTER SESSION, SELECT ANY DICTIONARY, FLASHBACK ANY TABLE, SELECT ANY TABLE, EXECUTE on DBMS_FLASHBACK | GG Extract |
| GGADMIN | 타겟 DBCS | CREATE SESSION, ALTER SESSION, SELECT ANY DICTIONARY, ALTER ANY TABLE, INSERT ANY TABLE, UPDATE ANY TABLE, DELETE ANY TABLE | GG Replicat |
| MIGRATION_USER | 소스 RDS | EXP_FULL_DATABASE, SELECT_CATALOG_ROLE, FLASHBACK ANY TABLE | expdp |
| MIGRATION_USER | 타겟 DBCS | IMP_FULL_DATABASE | impdp |

**[검증 `01_GG_Process #6`]** GGADMIN 계정 권한 확인
```sql
-- 소스/타겟 양쪽 실행
SELECT GRANTEE, GRANTED_ROLE FROM DBA_ROLE_PRIVS WHERE GRANTEE = 'GGADMIN';
SELECT GRANTEE, PRIVILEGE FROM DBA_SYS_PRIVS WHERE GRANTEE = 'GGADMIN';
```

### 0-4. NLS / 타임존 사전 확인

**[검증 `03_Data_Validation #21`]** NLS_CHARACTERSET — 소스/타겟 일치 확인
```sql
-- 소스와 타겟에서 각각 실행하여 비교
SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN (
    'NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET',
    'NLS_DATE_FORMAT', 'NLS_TIMESTAMP_FORMAT',
    'NLS_TIMESTAMP_TZ_FORMAT', 'NLS_LANGUAGE',
    'NLS_TERRITORY', 'NLS_SORT'
);

-- DB Timezone (TIMESTAMP WITH TIME ZONE 컬럼 존재 시 필수 확인)
SELECT DBTIMEZONE FROM DUAL;
```

> **주의**: NLS_CHARACTERSET 불일치 시 마이그레이션 중단. 한글 데이터 처리를 위해 AL32UTF8 권장.

---

## Phase 1: 소스 DB 준비 (AWS RDS)

**Phase 1 완료 기준 (→ Phase 2 전환 조건)**
- [ ] ENABLE_GOLDENGATE_REPLICATION = TRUE 확인
- [ ] Supplemental Logging (MIN) 활성화 확인
- [ ] PK 없는 테이블 ALL COLUMNS 로깅 적용 완료
- [ ] RDS Redo Log 보존 기간 ≥ 24h 확인
- [ ] GGADMIN 계정 권한 확인 완료

### 1-1. GoldenGate 파라미터 설정

**[검증 `01_GG_Process #1`]** ENABLE_GOLDENGATE_REPLICATION — SE는 기본 FALSE
```sql
-- AWS RDS에서 설정 (SE 제약: 수동 활성화 필수)
EXEC rdsadmin.rdsadmin_util.set_configuration('enable_goldengate_replication', 'true');

-- 확인
SELECT NAME, VALUE FROM V$PARAMETER WHERE NAME = 'enable_goldengate_replication';
-- 기대값: TRUE
```

**[검증 `01_GG_Process #2`]** Archive Log 모드 확인
```sql
SELECT LOG_MODE FROM V$DATABASE;
-- 기대값: ARCHIVELOG (RDS는 기본 ARCHIVELOG)
```

**[검증 `01_GG_Process #7`]** RDS Redo Log 보존 기간 — 최소 24시간
```sql
-- AWS RDS 설정 (Extract 장애 복구 대비)
EXEC rdsadmin.rdsadmin_util.set_configuration('archivelog retention hours', 48);
-- 권장: 48시간 (24시간은 최솟값, 복제 지연 고려 시 더 넉넉하게)

-- 확인
SELECT NAME, VALUE FROM V$PARAMETER WHERE NAME LIKE 'archivelog%';
```

**[검증 `01_GG_Process #5`]** Redo Log 그룹/크기 확인
```sql
SELECT GROUP#, MEMBERS, BYTES/1024/1024 AS MB, STATUS FROM V$LOG;
-- 최소 3그룹, 그룹당 500MB 이상 권장
```

### 1-2. Supplemental Logging 설정

**[검증 `01_GG_Process #3`]** 최소 Supplemental Logging
```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- 확인
SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;
-- 기대값: YES
```

**[검증 `01_GG_Process #4`]** PK 없는 테이블 ALL COLUMNS 로깅 — 전체 DB 대상
```sql
-- ■ 전체 DB: 시스템 스키마 제외 후 PK 없는 테이블 전체에 ALL COLUMNS 로깅 적용 스크립트 생성
SELECT 'ALTER TABLE ' || T.OWNER || '.' || T.TABLE_NAME ||
       ' ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;'
FROM DBA_TABLES T
WHERE T.OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER',
    'GSMUSER','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
    'ORDPLUGINS','ORDSYS','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA',
    'SYS$UMF','SYSBACKUP','SYSDG','SYSKM','SYSRAC','WMSYS','XDB','XS$NULL',
    'GGADMIN','GGS_TEMP','MIGRATION_USER'
)
AND T.TEMPORARY = 'N'           -- 임시 테이블 제외
AND T.EXTERNAL = 'NO'           -- External Table 제외 (지원 안 됨)
AND NOT EXISTS (
    SELECT 1 FROM DBA_CONSTRAINTS C
    WHERE C.OWNER = T.OWNER
    AND C.TABLE_NAME = T.TABLE_NAME
    AND C.CONSTRAINT_TYPE = 'P'
)
ORDER BY T.OWNER, T.TABLE_NAME;
-- 생성된 스크립트를 실행하여 전체 적용

-- 적용 확인 (전체 DB 기준)
SELECT LOG_GROUP_TYPE, COUNT(*) AS CNT
FROM DBA_LOG_GROUP_COLUMNS
GROUP BY LOG_GROUP_TYPE
ORDER BY LOG_GROUP_TYPE;

-- PK 없는 테이블 수 vs 적용된 ALL COLUMNS 로깅 수 비교
SELECT
    (SELECT COUNT(*) FROM DBA_TABLES T
     WHERE T.OWNER NOT IN (
         'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
         'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
         'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
     )
     AND TEMPORARY='N' AND EXTERNAL='NO'
     AND NOT EXISTS (
         SELECT 1 FROM DBA_CONSTRAINTS C
         WHERE C.OWNER=T.OWNER AND C.TABLE_NAME=T.TABLE_NAME AND C.CONSTRAINT_TYPE='P'
     )
    ) AS NO_PK_TABLES,
    (SELECT COUNT(DISTINCT LOG_GROUP_TABLE || '.' || LOG_GROUP_TABLE)
     FROM DBA_LOG_GROUPS
     WHERE LOG_GROUP_TYPE = 'USER LOG GROUP'
    ) AS SUPLOG_APPLIED;
-- NO_PK_TABLES = SUPLOG_APPLIED 이어야 함
```

**[검증 `05_Migration_Caution #21`]** 파티션 테이블 Supplemental Logging 별도 확인
```sql
-- 파티션 테이블도 동일하게 Supplemental Log 적용 여부 확인
SELECT PT.OWNER, PT.TABLE_NAME,
       CASE WHEN EXISTS (
           SELECT 1 FROM DBA_SUPPLEMENTAL_LOGGING SL
           WHERE SL.OWNER = PT.OWNER AND SL.LOG_GROUP_TABLE = PT.TABLE_NAME
       ) THEN 'OK' ELSE 'MISSING' END AS SUPLOG_STATUS
FROM DBA_PART_TABLES PT
WHERE PT.OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

### 1-3. Streams Pool 메모리 설정

**[검증 `05_Migration_Caution #3`]** SE는 Streams Pool 수동 설정 필요
```
-- AWS RDS Parameter Group에서 설정
-- streams_pool_size = 268435456  (256MB, 최소)
-- 권장: 512MB (536870912) — DB 크기 및 복제 대상 테이블 수에 따라 조정
-- AWS Console → RDS Parameter Group → 해당 파라미터 수정 후 DB 재기동
```

```sql
-- 적용 확인
SELECT NAME, VALUE/1024/1024 AS MB FROM V$PARAMETER WHERE NAME = 'streams_pool_size';
```

---

## Phase 2: 타겟 DB 준비 (OCI DBCS)

**Phase 2 완료 기준 (→ Phase 3 전환 조건)**
- [ ] OCI DBCS 정상 기동 확인
- [ ] NLS 파라미터 소스와 일치 확인
- [ ] 스키마 구조(DDL) 이전 완료 (INVALID 0건)
- [ ] **오브젝트 완전성 매트릭스 소스/타겟 COUNT 일치** (`2-5. 오브젝트 완전성 전수 비교`)
- [ ] **인덱스 전체 VALID 상태 (UNUSABLE 0건)**
- [ ] 특수 객체(Directory, External Table, MV, DB Link) 처리 계획 완료
- [ ] 타겟 Trigger DISABLE 스크립트 준비 완료
- [ ] FK DISABLE 스크립트 준비 완료

### 2-1. OCI DBCS 초기 설정

**[검증 `03_Data_Validation #21~22`]** NLS 파라미터 소스와 동일하게 설정
```sql
-- init.ora / spfile에서 소스와 동일하게 설정
-- ALTER SYSTEM SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS' SCOPE=SPFILE;
-- 재기동 후 확인
SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN ('NLS_CHARACTERSET','NLS_DATE_FORMAT','NLS_TIMESTAMP_TZ_FORMAT');
```

### 2-2. 스키마 구조 이전 (METADATA_ONLY)

```bash
# 소스 RDS에서 메타데이터 Export
expdp MIGRATION_USER/password@RDS_TNS \
    FULL=Y \
    CONTENT=METADATA_ONLY \
    DUMPFILE=metadata_%U.dmp \
    LOGFILE=metadata_export.log \
    EXCLUDE=STATISTICS \
    DIRECTORY=DATA_PUMP_DIR

# OCI Object Storage로 전송 후 DBCS에서 Download
oci os object bulk-upload \
    --bucket-name <DUMP_BUCKET> \
    --src-dir /rdsdbdata/userdirs/01/ \
    --prefix metadata/

# 타겟 DBCS에서 Import (구조만)
impdp MIGRATION_USER/password@OCI_TNS \
    FULL=Y \
    CONTENT=METADATA_ONLY \
    DUMPFILE=metadata_%U.dmp \
    LOGFILE=metadata_import.log \
    TABLE_EXISTS_ACTION=SKIP \
    EXCLUDE=STATISTICS \
    REMAP_TABLESPACE=<SOURCE_TS>:<TARGET_TS> \
    DIRECTORY=DATA_PUMP_DIR
```

> **주의**: Tablespace 이름이 소스/타겟 간 다를 경우 `REMAP_TABLESPACE` 파라미터 필수 (`02_Static_Schema #33~34`).

### 2-3. 타겟 스키마 구조 검증

**[검증 `02_Static_Schema #1~5`]** 테이블 구조 비교
```sql
-- 테이블 수 비교
SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

-- 컬럼 구조 상세 (소스/타겟 각각 실행 후 비교)
SELECT OWNER, TABLE_NAME, COLUMN_NAME, COLUMN_ID,
       DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE,
       NULLABLE, DATA_DEFAULT
FROM DBA_TAB_COLUMNS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME, COLUMN_ID;
```

**[검증 `02_Static_Schema #6~9`]** 인덱스 검증
```sql
-- BITMAP Index 확인 (SE 미지원 → 일반 Index로 대체 필요)
SELECT OWNER, INDEX_NAME, TABLE_NAME, INDEX_TYPE
FROM DBA_INDEXES
WHERE INDEX_TYPE = 'BITMAP'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- 있으면 impdp 후 타겟에서 FUNCTION-BASED 또는 일반 Index로 수동 대체

-- 전체 인덱스 상태 (UNUSABLE 없음 확인)
SELECT OWNER, INDEX_NAME, STATUS FROM DBA_INDEXES
WHERE STATUS != 'VALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- 기대값: 0건
```

**[검증 `02_Static_Schema #10~15`]** 제약조건 검증
```sql
-- PK/FK/UNIQUE/CHECK 제약 목록 및 상태
SELECT OWNER, TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE, STATUS
FROM DBA_CONSTRAINTS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
AND CONSTRAINT_TYPE IN ('P','R','U','C')
ORDER BY OWNER, TABLE_NAME;

-- DISABLED 제약 확인 (0건 목표)
SELECT OWNER, TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM DBA_CONSTRAINTS
WHERE STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**[검증 `02_Static_Schema #19~21`]** 시퀀스 검증
```sql
SELECT SEQUENCE_OWNER, SEQUENCE_NAME, INCREMENT_BY,
       MIN_VALUE, MAX_VALUE, CACHE_SIZE, LAST_NUMBER
FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY SEQUENCE_OWNER, SEQUENCE_NAME;
-- 타겟 LAST_NUMBER ≥ 소스 LAST_NUMBER + CACHE_SIZE 확인
```

**[검증 `02_Static_Schema #22~23`]** Synonym 검증
```sql
-- 유효하지 않은 Synonym 확인 (참조 객체 미존재)
SELECT S.OWNER, S.SYNONYM_NAME, S.OWNER, S.TABLE_NAME
FROM DBA_SYNONYMS S
WHERE NOT EXISTS (
    SELECT 1 FROM DBA_OBJECTS O
    WHERE O.OWNER = S.OWNER AND O.OBJECT_NAME = S.TABLE_NAME
)
AND S.OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- 기대값: 0건 (있으면 참조 객체 먼저 생성 후 재확인)
```

**[검증 `02_Static_Schema #37~38`]** INVALID 객체 재컴파일 (전체 DB)
```sql
-- INVALID 객체 조회
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY OWNER, OBJECT_TYPE;

-- ■ 전체 DB 재컴파일: 사용자 스키마 전체를 루프로 처리
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

-- 재컴파일 후 재확인 (기대값: 0건)
SELECT COUNT(*) AS STILL_INVALID FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);
```

**[검증 `02_Static_Schema #24~28`]** Procedure/Function/Package 상태
```sql
-- INVALID PL/SQL 객체 확인
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OBJECT_TYPE IN ('PROCEDURE','FUNCTION','PACKAGE','PACKAGE BODY','TRIGGER')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**[검증 `02_Static_Schema #29~32`]** 사용자/권한 비교
```sql
-- 사용자 목록 (시스템 계정 제외)
SELECT USERNAME, ACCOUNT_STATUS, DEFAULT_TABLESPACE
FROM DBA_USERS
WHERE USERNAME NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER',
    'GSMUSER','LBACSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
    'ORDPLUGINS','ORDSYS','SI_INFORMTN_SCHEMA','SYS$UMF','SYSBACKUP',
    'SYSDG','SYSKM','SYSRAC','WMSYS','XDB','XS$NULL'
)
ORDER BY USERNAME;

-- 롤 부여 현황 비교
SELECT GRANTEE, GRANTED_ROLE, ADMIN_OPTION FROM DBA_ROLE_PRIVS
WHERE GRANTEE NOT IN ('SYS','SYSTEM','DBA','IMP_FULL_DATABASE','EXP_FULL_DATABASE')
ORDER BY GRANTEE, GRANTED_ROLE;
```

### 2-4. Directory Object 및 External Table 처리

**[검증 `02_Static_Schema #35`]** Directory Object 재생성
```sql
-- 소스 Directory 목록 파악
SELECT OWNER, DIRECTORY_NAME, DIRECTORY_PATH FROM DBA_DIRECTORIES ORDER BY 2;
```
```sql
-- 타겟 DBCS에서 OCI 환경 경로로 재생성
CREATE OR REPLACE DIRECTORY <DIR_NAME> AS '/u01/app/oracle/admin/<DB_NAME>/dpdump/';
GRANT READ, WRITE ON DIRECTORY <DIR_NAME> TO <SCHEMA_USER>;
```

**[검증 `02_Static_Schema #36`]** External Table 처리
```sql
-- External Table 목록 확인
SELECT OWNER, TABLE_NAME, DEFAULT_DIRECTORY_NAME, ACCESS_PARAMETERS
FROM DBA_EXTERNAL_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```
> **처리 방안**:
> - External Table의 외부 파일을 OCI Object Storage 또는 DBCS 서버로 이관
> - 타겟 Directory 객체 경로를 OCI 환경에 맞게 수정
> - External Table DDL 재생성 후 데이터 접근 테스트

### 2-5. 오브젝트 완전성 전수 비교 (Object Completeness Check)

> **목적**: METADATA_ONLY impdp 직후, 소스의 모든 오브젝트 유형이 타겟에 누락 없이 생성되었는지 전수 비교
> **방법**: 소스/타겟에서 동일 쿼리 실행 → MINUS 비교 → 누락 항목 수동 보완 후 재확인

#### (A) 오브젝트 유형별 수량 매트릭스

```sql
-- 소스/타겟 양쪽 실행 후 OBJECT_TYPE별 COUNT 비교
SELECT OBJECT_TYPE, COUNT(*) AS CNT
FROM DBA_OBJECTS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS',
                    'AUDSYS','CTXSYS','DBSFWUSER','DVSYS','GGSYS',
                    'GSMADMIN_INTERNAL','LBACSYS','OJVMSYS','WMSYS','XDB')
AND OBJECT_TYPE NOT IN ('JAVA CLASS','JAVA DATA','JAVA RESOURCE')
GROUP BY OBJECT_TYPE
ORDER BY OBJECT_TYPE;
-- 소스/타겟 COUNT 불일치 항목 → 해당 유형 상세 비교 수행
```

#### (B) 테이블 완전성 비교

```sql
-- 소스에만 있고 타겟에 없는 테이블 식별
SELECT OWNER, TABLE_NAME FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, TABLE_NAME;
-- 소스/타겟 MINUS → 기대값: 0건

-- 테이블 압축(Compression) 속성 비교
SELECT OWNER, TABLE_NAME, COMPRESSION, COMPRESS_FOR
FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND COMPRESSION = 'ENABLED'
ORDER BY OWNER, TABLE_NAME;
-- 소스에 압축 테이블 존재 시 타겟도 동일 압축 방식 적용 여부 확인
```

#### (C) 인덱스 완전성 비교

```sql
-- ① 인덱스 전체 목록 비교 (Invisible 포함)
SELECT OWNER, INDEX_NAME, TABLE_NAME, INDEX_TYPE,
       UNIQUENESS, STATUS, VISIBILITY, PARTITIONED
FROM DBA_INDEXES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, TABLE_NAME, INDEX_NAME;
-- 소스/타겟 MINUS → 기대값: 0건

-- ② 인덱스 컬럼 구성 비교 (컬럼 순서 포함)
SELECT IC.INDEX_OWNER, IC.INDEX_NAME, IC.TABLE_NAME,
       IC.COLUMN_POSITION, IC.COLUMN_NAME, IC.DESCEND
FROM DBA_IND_COLUMNS IC
WHERE IC.INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY IC.INDEX_OWNER, IC.INDEX_NAME, IC.COLUMN_POSITION;

-- ③ Function-Based Index (FBI) 표현식 비교 — 표현식 문자열 소스/타겟 동일해야 함
SELECT IE.INDEX_OWNER, IE.INDEX_NAME, IE.TABLE_NAME,
       IE.COLUMN_POSITION, IE.COLUMN_EXPRESSION, IE.DESCEND
FROM DBA_IND_EXPRESSIONS IE
WHERE IE.INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY IE.INDEX_OWNER, IE.INDEX_NAME, IE.COLUMN_POSITION;

-- ④ Invisible Index 확인 (소스와 동일 VISIBILITY 설정 여부)
SELECT OWNER, INDEX_NAME, TABLE_NAME, VISIBILITY
FROM DBA_INDEXES
WHERE VISIBILITY = 'INVISIBLE'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

-- ⑤ 파티션 인덱스 (LOCAL / GLOBAL 구분)
SELECT PI.INDEX_OWNER, PI.INDEX_NAME, PI.TABLE_NAME,
       PI.PARTITIONING_TYPE, PI.LOCALITY, PI.ALIGNMENT
FROM DBA_PART_INDEXES PI
WHERE PI.INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY PI.INDEX_OWNER, PI.INDEX_NAME;

-- 파티션 인덱스 파티션별 상태 (UNUSABLE 없음 확인)
SELECT INDEX_OWNER, INDEX_NAME, PARTITION_NAME, STATUS
FROM DBA_IND_PARTITIONS
WHERE STATUS != 'USABLE'
AND INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건

-- ⑥ 전체 인덱스 VALID 상태 최종 확인
SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS, PARTITIONED
FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건 (UNUSABLE 없음)
```

#### (D) 제약조건 완전성 비교

```sql
-- 제약조건 전수 비교 (PK/UK/FK/CHECK)
SELECT OWNER, CONSTRAINT_NAME, TABLE_NAME, CONSTRAINT_TYPE, STATUS,
       SEARCH_CONDITION, R_OWNER, R_CONSTRAINT_NAME, DELETE_RULE
FROM DBA_CONSTRAINTS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND CONSTRAINT_TYPE IN ('P','U','R','C')
ORDER BY OWNER, TABLE_NAME, CONSTRAINT_TYPE;

-- DISABLED 제약조건 0건 확인 (FK는 GG 복제 중 DISABLE 허용)
SELECT OWNER, TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM DBA_CONSTRAINTS
WHERE STATUS = 'DISABLED'
AND CONSTRAINT_TYPE != 'R'  -- FK는 제외 (복제 중 의도적 DISABLE)
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건
```

#### (E) PL/SQL 오브젝트 완전성 및 INVALID 체크

```sql
-- Procedure / Function / Package / Package Body / Type / Type Body / Trigger
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS, LAST_DDL_TIME
FROM DBA_OBJECTS
WHERE OBJECT_TYPE IN (
    'PROCEDURE','FUNCTION','PACKAGE','PACKAGE BODY',
    'TYPE','TYPE BODY','TRIGGER','LIBRARY'
)
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, OBJECT_TYPE, OBJECT_NAME;

-- INVALID 객체 즉시 재컴파일
-- 단계 1: INVALID 목록 확인
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);

-- 단계 2: ■ 전체 DB 재컴파일 — 사용자 스키마 루프
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

-- 단계 3: 재컴파일 후 재확인 — 기대값: 0건
SELECT COUNT(*) AS INVALID_CNT
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);

-- 단계 4: 특정 오브젝트 수동 재컴파일 (COMPILE_SCHEMA 후에도 INVALID 잔존 시)
ALTER PROCEDURE <OWNER>.<PROC_NAME> COMPILE;
ALTER PACKAGE <OWNER>.<PKG_NAME> COMPILE;
ALTER PACKAGE <OWNER>.<PKG_NAME> COMPILE BODY;
ALTER TRIGGER <OWNER>.<TRG_NAME> COMPILE;
ALTER TYPE <OWNER>.<TYPE_NAME> COMPILE;
```

#### (F) View 완전성 비교

```sql
-- View 목록 및 컴파일 상태
SELECT OWNER, VIEW_NAME, TEXT_LENGTH
FROM DBA_VIEWS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, VIEW_NAME;

-- INVALID View 재컴파일
SELECT OWNER, OBJECT_NAME FROM DBA_OBJECTS
WHERE OBJECT_TYPE = 'VIEW' AND STATUS = 'INVALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- ALTER VIEW <OWNER>.<VIEW_NAME> COMPILE;
```

#### (G) 시퀀스 완전성 비교

```sql
-- 시퀀스 전체 속성 비교 (INCREMENT_BY / CACHE / CYCLE / ORDER 포함)
SELECT SEQUENCE_OWNER, SEQUENCE_NAME,
       MIN_VALUE, MAX_VALUE, INCREMENT_BY,
       CYCLE_FLAG, ORDER_FLAG, CACHE_SIZE, LAST_NUMBER
FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY SEQUENCE_OWNER, SEQUENCE_NAME;
-- LAST_NUMBER: 타겟 ≥ 소스 + CACHE_SIZE
-- INCREMENT_BY / CYCLE / ORDER / CACHE: 소스와 완전 일치 필수
```

#### (H) Synonym 완전성 비교

```sql
-- Public / Private Synonym 목록 비교
SELECT OWNER, SYNONYM_NAME, OWNER, TABLE_NAME, DB_LINK
FROM DBA_SYNONYMS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
   OR OWNER = 'PUBLIC'
ORDER BY OWNER, SYNONYM_NAME;

-- 참조 객체 존재 여부 (타겟에서)
SELECT S.OWNER, S.SYNONYM_NAME, S.OWNER, S.TABLE_NAME
FROM DBA_SYNONYMS S
WHERE NOT EXISTS (
    SELECT 1 FROM DBA_OBJECTS O
    WHERE O.OWNER = S.OWNER AND O.OBJECT_NAME = S.TABLE_NAME
)
AND S.DB_LINK IS NULL
AND S.OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건
```

#### (I) 권한/Profile 완전성 비교

```sql
-- 사용자 목록 및 적용 Profile 확인
SELECT USERNAME, ACCOUNT_STATUS, DEFAULT_TABLESPACE,
       TEMPORARY_TABLESPACE, PROFILE
FROM DBA_USERS
WHERE USERNAME NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER',
    'GSMUSER','LBACSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
    'ORDPLUGINS','ORDSYS','SI_INFORMTN_SCHEMA','SYS$UMF','SYSBACKUP',
    'SYSDG','SYSKM','SYSRAC','WMSYS','XDB','XS$NULL'
)
ORDER BY USERNAME;

-- Profile 속성 비교 (패스워드 정책 포함)
SELECT PROFILE, RESOURCE_NAME, RESOURCE_TYPE, LIMIT
FROM DBA_PROFILES
WHERE PROFILE NOT IN ('DEFAULT','ORA_STIG_PROFILE')
ORDER BY PROFILE, RESOURCE_TYPE, RESOURCE_NAME;

-- 롤/시스템/객체 권한 비교 (각각 소스/타겟 MINUS)
SELECT GRANTEE, GRANTED_ROLE, ADMIN_OPTION FROM DBA_ROLE_PRIVS
WHERE GRANTEE NOT IN ('SYS','SYSTEM','DBA','IMP_FULL_DATABASE','EXP_FULL_DATABASE')
ORDER BY GRANTEE, GRANTED_ROLE;

SELECT GRANTEE, PRIVILEGE, ADMIN_OPTION FROM DBA_SYS_PRIVS
WHERE GRANTEE NOT IN ('SYS','SYSTEM','DBA','IMP_FULL_DATABASE','EXP_FULL_DATABASE')
ORDER BY GRANTEE, PRIVILEGE;

SELECT GRANTEE, OWNER, TABLE_NAME, PRIVILEGE, GRANTABLE FROM DBA_TAB_PRIVS
WHERE GRANTEE NOT IN ('SYS','SYSTEM','DBA','PUBLIC','WMSYS')
ORDER BY GRANTEE, OWNER, TABLE_NAME;
```

#### 오브젝트 완전성 체크 결과 매트릭스 (기록용)

| 오브젝트 유형 | 소스 건수 | 타겟 건수 | 차이 | 판정 | 비고 |
|-------------|---------|---------|-----|------|------|
| TABLE | | | | - | |
| INDEX (NORMAL/UNIQUE) | | | | - | |
| INDEX (FBI) | | | | - | |
| INDEX (PARTITION LOCAL) | | | | - | |
| INDEX (PARTITION GLOBAL) | | | | - | |
| INDEX (INVISIBLE) | | | | - | |
| VIEW | | | | - | |
| SEQUENCE | | | | - | |
| PROCEDURE | | | | - | |
| FUNCTION | | | | - | |
| PACKAGE | | | | - | |
| PACKAGE BODY | | | | - | |
| TYPE | | | | - | |
| TYPE BODY | | | | - | |
| TRIGGER | | | | - | |
| SYNONYM (PRIVATE) | | | | - | |
| SYNONYM (PUBLIC) | | | | - | |
| MV | | | | - | |
| MV LOG | | | | - | |
| DB LINK | | | | - | |
| DIRECTORY | | | | - | |
| PROFILE | | | | - | |
| USER | | | | - | |
| CONSTRAINT (PK) | | | | - | |
| CONSTRAINT (FK) | | | | - | |
| CONSTRAINT (UNIQUE) | | | | - | |
| CONSTRAINT (CHECK) | | | | - | |
| SCHEDULER JOB | | | | - | |

---

### 2-6. 특수 객체 타겟 준비

**[검증 `04_Special_Objects - MV #1~3`]** MV 준비
```sql
-- 소스 MV 상세 파악
SELECT OWNER, MVIEW_NAME, REFRESH_METHOD, REFRESH_MODE, STALENESS,
       BUILD_MODE, REWRITE_ENABLED
FROM DBA_MVIEWS WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- MV Log 존재 여부 (FAST REFRESH 가능 여부)
SELECT LOG_OWNER, MASTER, LOG_TABLE, PRIMARY_KEY, ROWID, SEQUENCE
FROM DBA_MVIEW_LOGS WHERE LOG_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```
> **핵심**: OCI GG는 MV 자체를 복제하지 않음 → 타겟에서 수동 재생성 + REFRESH 필요

**[검증 `04_Special_Objects - Trigger #9~10`]** Trigger 목록 정리
```sql
-- 소스 Trigger 전체 목록 (INSTEAD OF 포함)
SELECT OWNER, TRIGGER_NAME, TRIGGER_TYPE, TRIGGERING_EVENT,
       OWNER, TABLE_NAME, STATUS
FROM DBA_TRIGGERS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME;

-- 타겟 Trigger DISABLE 스크립트 생성 (복제 중 이중 실행 방지)
SELECT 'ALTER TRIGGER ' || OWNER || '.' || TRIGGER_NAME || ' DISABLE;'
FROM DBA_TRIGGERS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER;
-- → 스크립트 저장: disable_triggers.sql
```

**[검증 `04_Special_Objects - DB Link #16~17`]** DB Link 처리 준비
```sql
-- 소스 DB Link 목록
SELECT OWNER, DB_LINK, USERNAME, HOST FROM DBA_DB_LINKS;

-- DB Link 의존 객체 (View/Proc) 식별
SELECT OWNER, NAME, TYPE FROM DBA_DEPENDENCIES
WHERE REFERENCED_TYPE = 'DATABASE LINK';
```
> **처리 방안**: OCI GG는 DB Link 복제 미지원 → 타겟 환경 네트워크에 맞게 수동 재생성, TNS/EZConnect 수정

**[검증 `04_Special_Objects - DBMS_JOB #23~24`]** DBMS_JOB 처리 준비
```sql
-- 소스 DBMS_JOB 전체 목록
SELECT JOB, LOG_USER, PRIV_USER, WHAT, INTERVAL, BROKEN, NEXT_DATE
FROM DBA_JOBS ORDER BY JOB;

-- 실행 중인 JOB 확인
SELECT JOB, FAILURES, WHAT FROM DBA_JOBS_RUNNING;
```
> **처리 방안**: DBMS_SCHEDULER로 전환 매핑 작업 사전 수행 (`05_Migration_Caution #6`)

---

## Phase 3: OCI GoldenGate 구성

**Phase 3 완료 기준 (→ Phase 4 전환 조건)**
- [ ] OCI GG Deployment 정상 동작 확인
- [ ] 소스/타겟 Connection 연결 테스트 PASS
- [ ] Extract/Pump/Replicat 파라미터 파일 검증 완료
- [ ] Heartbeat Table 추가 완료
- [ ] Trail File 저장소 (Object Storage) 연결 확인

### 3-1. OCI GG Deployment 확인

**[검증 `01_GG_Process #8`]**
- OCI Console → GoldenGate → Deployments → 버전 확인
- Oracle 19c SE 지원 버전인지 릴리즈 노트 검토
- 자동 업데이트 정책: 복제 중 자동 패치 비활성화 권장

### 3-2. Connection 설정

```
# OCI GG Console에서 Connection 생성

[Source Connection]
  Name: SRC_RDS_CONN
  Type: Oracle Database
  Host: <RDS_ENDPOINT>
  Port: 1521
  Service Name: <RDS_SERVICE_NAME>
  Username: GGADMIN / Password: <password>

[Target Connection]
  Name: TGT_DBCS_CONN
  Type: Oracle Database
  Host: <OCI_DBCS_PRIVATE_IP>
  Port: 1521
  Service Name: <DBCS_SERVICE_NAME>
  Username: GGADMIN / Password: <password>
```

**[검증 `01_GG_Process #9`]** 네트워크 연결 확인
```bash
# OCI GG Deployment에서 소스 RDS 접근 가능 여부
telnet <RDS_ENDPOINT> 1521
# 또는 sqlplus 연결 테스트
sqlplus GGADMIN/password@<RDS_ENDPOINT>:1521/<SERVICE>
```

### 3-3. Heartbeat Table 추가 (End-to-End LAG 정확 측정)

```
-- OCI GG Admin Server GGSCI
ADD HEARTBEATTABLE
-- GG가 소스/타겟에 Heartbeat 테이블 자동 생성 및 주기적 업데이트
-- INFO HEARTBEATTABLE 로 LAG 정확도 향상 확인
```

### 3-4. Extract 파라미터 설정

> **핵심**: expdp Export 전에 Extract를 등록하여 SCN 추적 시작 — Extract는 Phase 4의 expdp SCN 이후부터 실제 적용

```
-- GGSCI
ADD CREDENTIALSTORE
ALTER CREDENTIALSTORE ADD USER ggadmin@<SRC_TNS_ALIAS> ALIAS ggadmin_src

ADD EXTRACT EXT1, INTEGRATED TRANLOG, BEGIN NOW
ADD EXTTRAIL ./dirdat/aa, EXTRACT EXT1, MEGABYTES 500
```

```
-- Extract 파라미터 (EDIT PARAMS EXT1)
-- ■ 전체 DB 이전: 시스템 스키마 제외 후 전체 사용자 스키마 복제
EXTRACT EXT1
USERIDALIAS ggadmin_src DOMAIN OracleGoldenGate
EXTTRAIL ./dirdat/aa
SOURCETIMEZONE +09:00

-- SE 제약: DDL 복제는 지원 범위 내에서만 설정 (미지원 DDL → 수동 처리 절차 별도 수립)
DDL INCLUDE MAPPED OBJTYPE 'TABLE' OPTYPE CREATE, ALTER, DROP, TRUNCATE

-- ■ 전체 DB 복제: 와일드카드 사용 후 시스템 스키마 명시적 제외
-- 방법 1: 와일드카드 + TABLEEXCLUDE (권장 — 신규 스키마 자동 포함)
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
-- GoldenGate 자체 스키마 제외 (복제 대상에서 반드시 제외)
TABLEEXCLUDE GGADMIN.*;
TABLEEXCLUDE GGS_TEMP.*;
-- XMLTYPE Object-Relational 방식 테이블 확인 후 필요 시 제외
-- TABLEEXCLUDE <SCHEMA>.<XMLTYPE_TABLE>;

-- 전체 사용자 스키마 테이블/시퀀스 복제
TABLE *.*;
SEQUENCE *.*;
```

**[검증 `04_Special_Objects - DDL Replication #39`]** SE DDL 제약 확인
- SE에서 미지원 DDL 유형 목록 OCI GG 릴리즈 노트 기준으로 파악
- 지원 외 DDL 발생 시 수동 처리 절차 문서화 (`05_Migration_Caution #8`)

### 3-5. Data Pump (Trail Pump) 파라미터 설정

```
ADD EXTRACT PUMP1, EXTTRAILSOURCE ./dirdat/aa
ADD RMTTRAIL <OCI_OBJECT_STORAGE_TRAIL_PATH>/rt, EXTRACT PUMP1

-- EDIT PARAMS PUMP1
-- ■ 전체 DB 이전: Extract와 동일한 와일드카드 범위 사용
EXTRACT PUMP1
USERIDALIAS ggadmin_src DOMAIN OracleGoldenGate
RMTTRAIL <OCI_OBJECT_STORAGE_TRAIL_PATH>/rt
PASSTHRU
TABLE *.*;
SEQUENCE *.*;
```

**[검증 `01_GG_Process #17`]** OCI Object Storage 연결 확인
```
INFO EXTRACT PUMP1, DETAIL
-- Trail 저장소 접근 정상 여부 확인
```

### 3-6. Replicat 파라미터 설정

```
ADD REPLICAT REP1, INTEGRATED, EXTTRAIL <OCI_OBJECT_STORAGE_TRAIL_PATH>/rt

-- EDIT PARAMS REP1
REPLICAT REP1
USERIDALIAS ggadmin_tgt DOMAIN OracleGoldenGate
SOURCETIMEZONE +09:00

-- 소스/타겟 구조 완전 동일한 경우 ASSUMETARGETDEFS 사용 가능
-- Tablespace 리맵핑 등 구조 변경이 있으면 DEFS 파일 생성 후 SOURCEDEFS 사용
ASSUMETARGETDEFS

-- Trigger 이중 실행 방지 (필수)
SUPPRESSTRIGGERS

-- 초기 적재 중 충돌 처리 (데이터 동기화 완료 후 반드시 제거)
HANDLECOLLISIONS

-- ■ 전체 DB 이전: 와일드카드로 전체 사용자 스키마 매핑
-- 시스템 스키마는 Extract에서 이미 제외되므로 여기선 *.*로 전달되는 것만 처리
MAP *.*, TARGET *.*;
SEQUENCE *.*;
```

**[검증 `01_GG_Process #22`]** SUPPRESSTRIGGERS 적용 확인

---

## Phase 4: 초기 데이터 적재 (expdp / impdp)

**Phase 4 완료 기준 (→ Phase 5 전환 조건)**
- [ ] expdp Export 오류 0건
- [ ] impdp Import 오류 0건 (또는 허용 가능한 오류 원인 분석 완료)
- [ ] 타겟 FK DISABLE → Import 완료 (FK는 GG 동기화 중 DISABLE 유지)
- [ ] Row Count 초기 비교 오차 0% (SCN 고정 기준)
- [ ] 타겟 INVALID 객체 0건 확인 (데이터 적재 후 재컴파일)
- [ ] 인덱스 전체 VALID 상태 확인 (impdp 후 UNUSABLE 없음)
- [ ] 통계정보 처리 전략 결정 및 수행 (옵션 A 또는 B)

### 4-1. UNDO 및 Flashback 사전 확인

**expdp FLASHBACK_SCN 사용 전 확인 사항**:
```sql
-- UNDO_RETENTION 확인 (Export 소요 시간 + 여유분 이상이어야 함)
SELECT VALUE FROM V$PARAMETER WHERE NAME = 'undo_retention';
-- 부족하면: ALTER SYSTEM SET UNDO_RETENTION=<seconds> SCOPE=BOTH;

-- UNDO 테이블스페이스 여유 공간 확인
SELECT TABLESPACE_NAME,
       ROUND(SUM(BYTES)/1024/1024/1024, 2) AS FREE_GB
FROM DBA_FREE_SPACE
WHERE TABLESPACE_NAME LIKE '%UNDO%'
GROUP BY TABLESPACE_NAME;

-- MIGRATION_USER의 Flashback 권한 확인
SELECT GRANTEE, PRIVILEGE FROM DBA_SYS_PRIVS
WHERE GRANTEE = 'MIGRATION_USER' AND PRIVILEGE = 'FLASHBACK ANY TABLE';
```

> **주의**: UNDO_RETENTION 부족 시 대용량 Export 중 ORA-01555 (Snapshot too old) 발생 가능.
> AWS RDS에서 UNDO_RETENTION 변경이 제한될 경우 `FLASHBACK_TIME` 파라미터 사용 또는 야간 저부하 시간대 Export 권장.

### 4-2. SCN 고정 및 Export

```bash
# 1. Export 직전 SCN 확인 및 기록 (이 SCN으로 GG Extract 시작점 설정)
sqlplus -S MIGRATION_USER/password@RDS_TNS <<'EOF'
SELECT CURRENT_SCN, SYSDATE FROM V$DATABASE;
EOF
# → SCN 값 기록 (예: 98765432)

# 2. Extract 등록 (SCN 기점 지정 — Phase 3에서 이미 ADD EXTRACT했다면 SCN을 아래와 같이 지정)
# GGSCI: DELETE EXTRACT EXT1 (기존 삭제 후 SCN 지정하여 재등록)
# ADD EXTRACT EXT1, INTEGRATED TRANLOG, BEGIN SCN 98765432

# 3. DATA_ONLY Export (SCN 고정, METADATA는 Phase 2에서 이미 완료)
expdp MIGRATION_USER/password@RDS_TNS \
    FULL=Y \
    CONTENT=DATA_ONLY \
    FLASHBACK_SCN=98765432 \
    DUMPFILE=fulldata_%U.dmp \
    FILESIZE=10G \
    PARALLEL=4 \
    LOGFILE=fulldata_export.log \
    EXCLUDE=STATISTICS \
    DIRECTORY=DATA_PUMP_DIR

# ※ Oracle SE에서 PARALLEL 파라미터는 EE 대비 제한적으로 동작할 수 있음
# ※ PARALLEL=1로 시작하고 성능 확인 후 조정 권장

# 4. Dump 파일을 OCI Object Storage로 전송
oci os object bulk-upload \
    --bucket-name <DUMP_BUCKET> \
    --src-dir /rdsdbdata/userdirs/01/ \
    --prefix fulldata/ \
    --multipart-threshold 100MB
```

### 4-3. 타겟 FK 비활성화 및 Import

```bash
# 1. 타겟 DBCS에서 FK Constraint 비활성화 (TRUNCATE + Import 중 무결성 오류 방지)
sqlplus MIGRATION_USER/password@OCI_TNS <<'EOF'
SPOOL disable_fk.sql
SELECT 'ALTER TABLE '||OWNER||'.'||TABLE_NAME||
       ' DISABLE CONSTRAINT '||CONSTRAINT_NAME||';'
FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME;
SPOOL OFF
@disable_fk.sql
COMMIT;
EOF

# 2. 타겟 Trigger 비활성화 (GG 복제 전 이중 실행 방지)
# Phase 2에서 준비한 disable_triggers.sql 실행
sqlplus MIGRATION_USER/password@OCI_TNS @disable_triggers.sql

# 3. OCI Object Storage에서 Dump 파일 다운로드
oci os object bulk-download \
    --bucket-name <DUMP_BUCKET> \
    --download-dir /u01/backup/dump/ \
    --prefix fulldata/

# 4. impdp 실행 (데이터만)
impdp MIGRATION_USER/password@OCI_TNS \
    FULL=Y \
    CONTENT=DATA_ONLY \
    DUMPFILE=fulldata_%U.dmp \
    PARALLEL=4 \
    LOGFILE=fulldata_import.log \
    TABLE_EXISTS_ACTION=TRUNCATE \
    REMAP_TABLESPACE=<SOURCE_TS>:<TARGET_TS> \
    DIRECTORY=DATA_PUMP_DIR
```

### 4-4. 통계정보(Statistics) 처리 전략

> **핵심 원칙**: expdp에서 `EXCLUDE=STATISTICS`로 통계를 제외했으므로, 타겟 DB의 통계는 별도 처리 필요.
> 데이터가 없거나 적재 중인 상태에서 통계 수집 시 쓸모없는 통계가 생성됨 → **데이터 완전 적재 + GG 동기화 완료 후** 수집 필수.

#### 옵션 A (권장): 소스 전체 DB 통계를 Export → 타겟에 Import

```sql
-- [소스 RDS에서 실행] 전체 DB 통계를 스테이징 테이블로 Export
BEGIN
    DBMS_STATS.CREATE_STAT_TABLE(
        ownname  => 'MIGRATION_USER',
        stattab  => 'STATS_EXPORT_TABLE',
        tblspace => 'USERS'
    );
END;
/

-- ■ 전체 DB 통계 한 번에 Export (스키마별 반복 불필요)
BEGIN
    DBMS_STATS.EXPORT_DATABASE_STATS(
        stattab  => 'STATS_EXPORT_TABLE',
        statown  => 'MIGRATION_USER'
    );
END;
/
-- EXPORT_DATABASE_STATS는 모든 사용자 스키마 + 딕셔너리 통계를 한 번에 처리

-- 데이터 딕셔너리 통계 별도 Export (옵티마이저 내부 통계, 선택사항)
BEGIN
    DBMS_STATS.EXPORT_DICTIONARY_STATS(
        stattab => 'STATS_EXPORT_TABLE',
        statown => 'MIGRATION_USER'
    );
END;
/
```

```bash
# STATS_EXPORT_TABLE을 expdp로 별도 Export
expdp MIGRATION_USER/password@RDS_TNS \
    TABLES=MIGRATION_USER.STATS_EXPORT_TABLE \
    DUMPFILE=stats_export.dmp \
    LOGFILE=stats_export.log \
    DIRECTORY=DATA_PUMP_DIR

# OCI Object Storage로 전송 후 타겟 DBCS에서 Import
oci os object bulk-upload \
    --bucket-name <DUMP_BUCKET> \
    --src-dir /rdsdbdata/userdirs/01/ \
    --prefix stats/
```

```sql
-- [타겟 DBCS에서 실행] STATS_EXPORT_TABLE Import 후 전체 DB 통계 일괄 적용
-- impdp로 MIGRATION_USER.STATS_EXPORT_TABLE 먼저 Import 후 실행:

BEGIN
    DBMS_STATS.IMPORT_DATABASE_STATS(
        stattab => 'STATS_EXPORT_TABLE',
        statown => 'MIGRATION_USER',
        force   => TRUE     -- 기존 통계 덮어쓰기
    );
END;
/
-- IMPORT_DATABASE_STATS: 전체 사용자 스키마 통계를 한 번에 Import

-- 통계 적용 확인 (전체 DB 기준)
SELECT OWNER,
       COUNT(*) AS TABLE_CNT,
       SUM(CASE WHEN LAST_ANALYZED IS NULL THEN 1 ELSE 0 END) AS NO_STATS_CNT,
       MIN(LAST_ANALYZED) AS OLDEST_STATS,
       MAX(LAST_ANALYZED) AS NEWEST_STATS
FROM DBA_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
GROUP BY OWNER
ORDER BY NO_STATS_CNT DESC;
-- NO_STATS_CNT = 0 목표 (모든 스키마의 모든 테이블에 통계 존재)
```

#### 옵션 B (대안): 타겟에서 Fresh 통계 수집

> GG 동기화 안정화 후 (Cut-over D-1), 전체 DB 통계를 타겟에서 새로 수집

```sql
-- [타겟 DBCS에서 실행] — GG LAG < 30초 안정화 확인 후
-- ■ 전체 DB 통계 한 번에 수집 (CASCADE=TRUE: 인덱스 통계 포함)
BEGIN
    DBMS_STATS.GATHER_DATABASE_STATS(
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        cascade          => TRUE,
        degree           => 2,          -- Oracle SE: Parallel 제한, 2 이하 권장
        method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
        no_invalidate    => FALSE,      -- 관련 커서 즉시 무효화
        options          => 'GATHER'    -- 기존 통계 여부 무관하게 전체 수집
    );
END;
/
-- ※ Oracle SE에서는 DEGREE > 2 설정 시 실제 병렬도가 제한될 수 있음
-- ※ 대용량 DB에서 GATHER_DATABASE_STATS는 장시간 소요 가능 → D-1 야간 배치 실행 권장
```

#### 통계 수집 후 검증 (전체 DB 기준)

```sql
-- ■ 전체 DB: 스키마별 통계 존재 현황 요약
SELECT OWNER,
       COUNT(*) AS TABLE_CNT,
       SUM(CASE WHEN LAST_ANALYZED IS NULL THEN 1 ELSE 0 END) AS NO_STATS,
       SUM(CASE WHEN LAST_ANALYZED IS NOT NULL THEN 1 ELSE 0 END) AS HAS_STATS
FROM DBA_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL'
)
GROUP BY OWNER
ORDER BY NO_STATS DESC, OWNER;
-- 기대값: 모든 스키마의 NO_STATS = 0

-- 통계 없는 인덱스 확인 (전체 DB)
SELECT OWNER, INDEX_NAME, TABLE_NAME, LAST_ANALYZED
FROM DBA_INDEXES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
AND LAST_ANALYZED IS NULL
ORDER BY OWNER, TABLE_NAME;
-- 기대값: 0건

-- 히스토그램 현황 비교 (소스/타겟 — 전체 DB)
SELECT OWNER, TABLE_NAME, COLUMN_NAME, HISTOGRAM, NUM_BUCKETS
FROM DBA_TAB_COL_STATISTICS
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
AND HISTOGRAM != 'NONE'
ORDER BY OWNER, TABLE_NAME, COLUMN_NAME;
-- 소스와 동일한 컬럼에 히스토그램 생성되었는지 확인

-- 통계 기반 NUM_ROWS 소스/타겟 비교 (전체 DB)
SELECT OWNER, TABLE_NAME, NUM_ROWS, BLOCKS, AVG_ROW_LEN, LAST_ANALYZED
FROM DBA_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY OWNER, TABLE_NAME;
```

### 4-5. Import 후 오브젝트 상태 확인 (INVALID / 인덱스)

**impdp 완료 직후 — INVALID 객체 재확인 (데이터 적재로 인한 컴파일 상태 변화 체크)**
```sql
-- INVALID 객체 전수 확인 (기대값: 0건)
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS, LAST_DDL_TIME
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY OWNER, OBJECT_TYPE;

-- ■ INVALID 있으면 즉시 전체 DB 재컴파일
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

-- 재컴파일 후 재확인 (기대값: 0건)
SELECT COUNT(*) AS INVALID_CNT FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);
```

**인덱스 UNUSABLE 확인 (impdp DATA_ONLY 적재 후 인덱스 상태 체크)**
```sql
-- 전체 인덱스 상태 확인
SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS, PARTITIONED
FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건

-- 파티션 인덱스 파티션별 상태
SELECT INDEX_OWNER, INDEX_NAME, PARTITION_NAME, STATUS
FROM DBA_IND_PARTITIONS
WHERE STATUS != 'USABLE'
AND INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건

-- UNUSABLE 인덱스 발견 시 재빌드
ALTER INDEX <OWNER>.<INDEX_NAME> REBUILD;
-- 파티션 인덱스의 경우:
ALTER INDEX <OWNER>.<INDEX_NAME> REBUILD PARTITION <PARTITION_NAME>;
```

### 4-6. Import 후 초기 Row Count 확인

**[검증 `03_Data_Validation #1`]** SCN 고정 시점 기준 Row Count 비교
```sql
-- 소스에서 (FLASHBACK_SCN 시점 기준 — 직접 COUNT 수행)
SELECT TABLE_NAME, COUNT(*) AS CNT
FROM (SELECT TABLE_NAME FROM DBA_TABLES WHERE OWNER='<SCHEMA>')
-- 각 테이블별 직접 COUNT(*) 실행 (대용량 테이블은 파티션 단위)
;

-- 타겟에서 동일 방식 실행 후 비교
-- 오차 허용: 0% (SCN 고정 기준 DATA_ONLY import이므로 완전 일치 목표)
```

---

## Phase 5: 델타 동기화 (OCI GG 복제)

**Phase 5 완료 기준 (→ Phase 6 전환 조건)**
- [ ] Extract/Pump/Replicat 모두 RUNNING
- [ ] Extract LAG < 30초 (24시간 연속 유지)
- [ ] Replicat LAG < 30초 (24시간 연속 유지)
- [ ] Discard 파일 레코드 0건
- [ ] Trail File 용량 정상 범위 내

### 5-1. GG 복제 시작

```
-- GGSCI (OCI GG Admin Server)
-- Extract를 expdp SCN 기준점부터 시작
START EXTRACT EXT1 ATCSN 98765432
-- ※ ATCSN: 해당 SCN을 포함하는 트랜잭션부터 적용 (expdp SCN 이후 커밋 누락 방지)
-- ※ AFTERCSN은 해당 SCN 이후 트랜잭션부터 — expdp와의 경계에서 데이터 누락 가능성 있음

-- Pump 시작
START EXTRACT PUMP1

-- Replicat 시작 (HANDLECOLLISIONS 활성화 — 초기 적재 데이터와 충돌 자동 처리)
START REPLICAT REP1
```

### 5-2. GG 프로세스 상태 모니터링

**[검증 `01_GG_Process #10~14`]** Extract 상태 확인
```
STATUS EXTRACT EXT1       -- 기대값: RUNNING
LAG EXTRACT EXT1          -- 기대값: < 30초
INFO EXTRACT EXT1, DETAIL -- Checkpoint SCN 전진 확인
VIEW REPORT EXT1          -- ABEND/ERROR 없음 확인
```

**[검증 `01_GG_Process #12`]** Trail 파일 생성 확인
```
INFO EXTRACT EXT1, SHOWCH
-- Trail 파일 생성 및 용량 증가 확인
```

**[검증 `01_GG_Process #13`]** Checkpoint SCN 진행 확인
```
INFO EXTRACT EXT1, SHOWCH
-- Read Checkpoint SCN이 지속적으로 증가하는지 확인
-- Write Checkpoint와의 Gap이 줄어드는지 확인
```

**[검증 `01_GG_Process #15~17`]** Pump 상태 확인
```
STATUS EXTRACT PUMP1      -- 기대값: RUNNING
LAG EXTRACT PUMP1         -- 기대값: < 30초
-- OCI Object Storage Trail 파일 저장 확인
```

**[검증 `01_GG_Process #18~23`]** Replicat 상태 확인
```
STATUS REPLICAT REP1      -- 기대값: RUNNING
LAG REPLICAT REP1         -- 기대값: < 30초
STATS REPLICAT REP1 TOTAL -- Insert/Update/Delete 건수 증가 확인
VIEW REPORT REP1          -- ABEND/ERROR 없음 확인
-- Discard 파일 확인 (0건 유지)
```

**[검증 `01_GG_Process #24`]** Trail File 용량 모니터링
```
INFO EXTRACT EXT1, SHOWCH
-- LOB 복제 시 Trail 급증 주의 (Object Storage 임계치 알람 설정)
```

### 5-3. LAG 안정화 확인 체크리스트

- [ ] Extract LAG < 30초 — 24시간 연속 유지
- [ ] Replicat LAG < 30초 — 24시간 연속 유지
- [ ] Discard 파일 누적 건수 = 0
- [ ] Trail File 용량 안정적 (급증 없음)
- [ ] Extract/Replicat ABEND 이력 없음
- [ ] Heartbeat Table 정상 업데이트 확인

---

## Phase 6: 검증 (Validation)

> **전제**: Phase 5 안정화 확인 (LAG < 30초, 24시간+ 유지) 후 전수 검증 수행
> **결과 기록**: OCI_GG_Validation_Plan_20260313.xlsx 각 시트 결과(Result) 컬럼에 PASS/FAIL/WARN 기재

### 6-1. GG 프로세스 검증 (01_GG_Process — 28항목)

| 영역 | 항목 수 | 핵심 확인 |
|------|---------|-----------|
| Pre-Check | 9 | 파라미터, Archive Log, Supplemental Log, GGADMIN 권한, 네트워크 |
| Extract | 5 | RUNNING, LAG < 30초, Trail 생성, SCN 진행, ABEND 없음 |
| Data Pump | 3 | RUNNING, LAG < 30초, Object Storage 연결 |
| Replicat | 6 | RUNNING, LAG < 30초, Stats 증가, Discard 0건, SUPPRESSTRIGGERS |
| Trail File | 2 | 용량 모니터링, 보존 정책 설정 |
| 상시운영 | 3 | LAG 알람, GGADMIN 비번 만료 정책, 자동 패치 |

### 6-2. 정적 구조 검증 (02_Static_Schema — 38항목)

**#1~5 테이블 구조 비교**
```sql
-- 소스/타겟 동일 쿼리 실행 후 MINUS 비교
SELECT OWNER, TABLE_NAME, COLUMN_NAME, COLUMN_ID,
       DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE, NULLABLE
FROM DBA_TAB_COLUMNS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME, COLUMN_ID;
```

**#6~9 인덱스 완전성 검증** — GG 복제 안정화 후 재확인
```sql
-- ① 인덱스 수/이름/유형 비교 (소스/타겟 MINUS)
SELECT OWNER, INDEX_NAME, TABLE_NAME, INDEX_TYPE, UNIQUENESS, VISIBILITY
FROM DBA_INDEXES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, TABLE_NAME, INDEX_NAME;

-- ② 인덱스 컬럼 구성 비교 (순서 포함)
SELECT INDEX_OWNER, INDEX_NAME, COLUMN_POSITION, COLUMN_NAME, DESCEND
FROM DBA_IND_COLUMNS
WHERE INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY INDEX_OWNER, INDEX_NAME, COLUMN_POSITION;

-- ③ FBI 표현식 비교
SELECT INDEX_OWNER, INDEX_NAME, COLUMN_POSITION, COLUMN_EXPRESSION
FROM DBA_IND_EXPRESSIONS
WHERE INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY INDEX_OWNER, INDEX_NAME, COLUMN_POSITION;

-- ④ 파티션 인덱스 (LOCAL/GLOBAL) 비교
SELECT INDEX_OWNER, INDEX_NAME, TABLE_NAME, PARTITIONING_TYPE, LOCALITY, ALIGNMENT
FROM DBA_PART_INDEXES
WHERE INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY INDEX_OWNER, INDEX_NAME;

-- ⑤ 전체 인덱스 VALID 상태 (UNUSABLE 0건)
SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS, PARTITIONED
FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건

-- ⑥ 인덱스 통계 존재 여부 (LAST_ANALYZED IS NULL 없음 확인)
SELECT OWNER, INDEX_NAME, TABLE_NAME, LAST_ANALYZED, NUM_ROWS, DISTINCT_KEYS
FROM DBA_IND_STATISTICS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED IS NULL
ORDER BY OWNER, INDEX_NAME;
-- 기대값: 0건 (모든 인덱스에 통계 존재)
```

**#10~15 제약조건 검증** — Phase 2-3 쿼리 재실행 후 확인

**#19~21 시퀀스 검증**
```sql
-- 타겟 LAST_NUMBER ≥ 소스 LAST_NUMBER + CACHE_SIZE 확인 (필수)
-- 소스/타겟 각각 실행하여 Gap 계산
SELECT SEQUENCE_OWNER, SEQUENCE_NAME, LAST_NUMBER, CACHE_SIZE
FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**#37~38 INVALID 객체 0건** — Phase 2-3 재확인

### 6-3. 데이터 정합성 검증 (03_Data_Validation — 25항목)

**#1 전체 Row Count 비교**
```sql
-- 소스/타겟 각각 실행하여 비교
-- 핵심 테이블 대상 직접 COUNT(*) 수행 권장
SELECT 'SELECT COUNT(*) FROM ' || OWNER || '.' || TABLE_NAME || ';'
FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME;
```

**#2 대용량 테이블 별도 검증** (`03_Data_Validation #2`)
```sql
-- 1억 건 이상 테이블 파티션 단위 분할 비교
SELECT OWNER, TABLE_NAME, PARTITION_NAME, NUM_ROWS
FROM DBA_TAB_PARTITIONS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
AND NUM_ROWS > 10000000
ORDER BY OWNER, TABLE_NAME, PARTITION_POSITION;
```

**#4~6 Checksum 비교**
```sql
-- ORA_HASH는 실제 데이터 컬럼으로 계산 (ROWID는 소스/타겟 다르므로 절대 사용 금지)
-- PK + 핵심 컬럼 기반 체크섬 (소스/타겟 동일 쿼리 실행 후 결과 비교)
SELECT
    COUNT(*) AS CNT,
    SUM(ORA_HASH(
        TO_CHAR(<PK_COL>) || '|' ||
        TO_CHAR(<COL1>)   || '|' ||
        TO_CHAR(<COL2>)
    )) AS CHECKSUM
FROM <SCHEMA>.<TABLE_NAME>;

-- 핵심 테이블 집계 비교
SELECT
    SUM(<NUMBER_COL>) AS S,
    MAX(<NUMBER_COL>) AS MX,
    MIN(<NUMBER_COL>) AS MN,
    COUNT(DISTINCT <KEY_COL>) AS DSTCT
FROM <SCHEMA>.<TABLE_NAME>;
```

**#7~9 샘플 데이터 비교**
```sql
-- PK 기준 최신 1000건 소스/타겟 직접 비교
SELECT * FROM (
    SELECT <PK_COL>, <COL1>, <COL2>, <UPDATED_DATE>
    FROM <SCHEMA>.<TABLE_NAME>
    ORDER BY <UPDATED_DATE> DESC
) WHERE ROWNUM <= 1000;

-- NULL 비율 비교
SELECT COLUMN_NAME,
       COUNT(*) AS TOTAL,
       SUM(CASE WHEN <COL> IS NULL THEN 1 ELSE 0 END) AS NULL_CNT,
       ROUND(SUM(CASE WHEN <COL> IS NULL THEN 1 ELSE 0 END)/COUNT(*)*100,2) AS NULL_PCT
FROM <SCHEMA>.<TABLE_NAME>
GROUP BY COLUMN_NAME;
```

**#10~14 LOB 검증**
```sql
-- LOB 건수 및 총 크기 비교 (소스/타겟 동일 쿼리)
SELECT L.TABLE_NAME, L.COLUMN_NAME,
       COUNT(*) AS ROW_CNT,
       SUM(DBMS_LOB.GETLENGTH(T.<LOB_COL>)) AS TOTAL_BYTES
FROM <SCHEMA>.<TABLE_NAME> T, DBA_LOBS L
WHERE L.OWNER = '<SCHEMA>'
AND L.TABLE_NAME = '<TABLE_NAME>'
AND L.COLUMN_NAME = '<LOB_COL>'
GROUP BY L.TABLE_NAME, L.COLUMN_NAME;

-- EMPTY_LOB vs NULL 처리 일관성 확인
SELECT
    SUM(CASE WHEN <LOB_COL> IS NULL THEN 1 ELSE 0 END) AS NULL_CNT,
    SUM(CASE WHEN DBMS_LOB.GETLENGTH(<LOB_COL>) = 0 THEN 1 ELSE 0 END) AS EMPTY_CNT
FROM <SCHEMA>.<TABLE_NAME>;

-- BasicFile → SecureFile 전환 여부 확인 (타겟에서)
SELECT OWNER, TABLE_NAME, COLUMN_NAME, SECUREFILE
FROM DBA_LOBS WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- SECUREFILE='YES'이면 SecureFile, 'NO'이면 BasicFile
```

**#15~20 데이터 타입 특이 사항**
```sql
-- DATE 컬럼 시간 정보 확인 (HH24:MI:SS 유실 여부)
SELECT TO_CHAR(<DATE_COL>, 'YYYY-MM-DD HH24:MI:SS')
FROM <SCHEMA>.<TABLE_NAME>
WHERE <DATE_COL> > SYSDATE - 7
AND ROWNUM <= 100;

-- TIMESTAMP WITH TIME ZONE: NLS_TIMESTAMP_TZ_FORMAT 확인
SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER = 'NLS_TIMESTAMP_TZ_FORMAT';
-- DB Timezone 비교 (소스/타겟 동일해야 함)
SELECT DBTIMEZONE FROM DUAL;

-- XMLTYPE 컬럼 데이터 건수 확인 (소스/타겟)
-- XMLTYPE 스토리지 방식 확인
SELECT OWNER, TABLE_NAME, COLUMN_NAME, STORAGE
FROM DBA_XML_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- ROWID 의존 컬럼/로직 식별 (애플리케이션 코드 점검 필요)
SELECT OWNER, NAME, TYPE, TEXT
FROM DBA_SOURCE
WHERE UPPER(TEXT) LIKE '%ROWID%'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**#21~23 NLS 검증**
```sql
-- 한글/특수문자 샘플 확인
SELECT <KOREAN_COL>, LENGTHB(<KOREAN_COL>), LENGTH(<KOREAN_COL>)
FROM <SCHEMA>.<TABLE_NAME>
WHERE LENGTHB(<KOREAN_COL>) != LENGTH(<KOREAN_COL>)
AND ROWNUM <= 20;
```

**#24~25 참조 무결성 검증**
```sql
-- Orphan Row 확인 (FK 참조 부모 없는 자식 레코드)
SELECT COUNT(*) AS ORPHAN_CNT
FROM <CHILD_SCHEMA>.<CHILD_TABLE> C
WHERE NOT EXISTS (
    SELECT 1 FROM <PARENT_SCHEMA>.<PARENT_TABLE> P
    WHERE P.<PK_COL> = C.<FK_COL>
);
-- 기대값: 0건

-- FK DISABLED 상태로 Import 시 무결성 오류 데이터 확인
SELECT OWNER, TABLE_NAME, CONSTRAINT_NAME, STATUS
FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R'
AND STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

### 6-4. 특수 객체 검증 (04_Special_Objects — 42항목)

**MV 검증 (#1~8)**
```sql
-- 타겟 MV STALENESS 확인
SELECT OWNER, MVIEW_NAME, STALENESS FROM DBA_MVIEWS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- MV Row Count 소스/타겟 비교
SELECT COUNT(*) FROM <SCHEMA>.<MV_NAME>;

-- MV REFRESH 테스트
EXEC DBMS_MVIEW.REFRESH('<SCHEMA>.<MV_NAME>', 'C');
```

**Trigger 검증 (#9~15)**
```sql
-- Trigger 상태 확인 (복제 중 DISABLED 여부)
SELECT OWNER, TRIGGER_NAME, STATUS FROM DBA_TRIGGERS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
AND STATUS = 'ENABLED';
-- 복제 중에는 기대값: 0건 (모두 DISABLED)
```

**DB Link 검증 (#16~22)**
```sql
-- 타겟 DB Link 연결 테스트
SELECT * FROM DUAL@<DB_LINK_NAME>;

-- DB Link 의존 객체 재컴파일 후 VALID 확인
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**DBMS_JOB / DBMS_SCHEDULER 검증 (#23~29)**
```sql
-- 타겟 SCHEDULER JOB 확인
SELECT JOB_NAME, STATE, LAST_RUN_DURATION, NEXT_RUN_DATE
FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

-- 실행 주기 소스 INTERVAL과 동일 여부 확인
SELECT JOB_NAME, REPEAT_INTERVAL FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**Sequence 검증 (#30~33)**
```sql
-- 타겟 LAST_NUMBER ≥ 소스 LAST_NUMBER + CACHE_SIZE
-- 소스에서 실행:
SELECT SEQUENCE_NAME, LAST_NUMBER, CACHE_SIZE,
       LAST_NUMBER + CACHE_SIZE AS REQUIRED_MIN
FROM DBA_SEQUENCES WHERE SEQUENCE_OWNER = '<SCHEMA>';

-- 타겟에서 실행:
SELECT SEQUENCE_NAME, LAST_NUMBER FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER = '<SCHEMA>';
-- 타겟 LAST_NUMBER > 소스 REQUIRED_MIN 확인
```

**파티션 테이블 검증 (#34~38)**
```sql
-- 파티션별 Row Count 비교 (소스/타겟)
SELECT OWNER, TABLE_NAME, PARTITION_NAME, NUM_ROWS
FROM DBA_TAB_PARTITIONS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME, PARTITION_POSITION;

-- 파티션 Pruning 정상 동작 확인
EXPLAIN PLAN FOR
SELECT * FROM <SCHEMA>.<PARTITION_TABLE>
WHERE <PARTITION_KEY> = <VALUE>;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- "PARTITION RANGE SINGLE" 또는 특정 파티션만 접근하는지 확인

-- 파티션 테이블 Supplemental Log 적용 여부 재확인
SELECT OWNER, NAME, TYPE FROM DBA_SUPPLEMENTAL_LOGGING
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
```

**DDL Replication 검증 (#39~42)**
```sql
-- 복제 후 DDL 변경이 타겟에 자동 반영되는지 테스트
-- (테스트 테이블 생성/컬럼 추가 후 타겟 확인)
-- 지원되지 않는 DDL 유형 목록 작성 및 수동 처리 절차 확정
```

### 6-5. 통계정보(Statistics) 검증

> GG 동기화 안정화 후, Cut-over D-1에 통계 최신화 여부 확인

**테이블 통계 완전성 확인**
```sql
-- 통계 없는 테이블 0건 확인
SELECT OWNER, TABLE_NAME, NUM_ROWS, BLOCKS, AVG_ROW_LEN, LAST_ANALYZED
FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED IS NULL
ORDER BY OWNER, TABLE_NAME;
-- 기대값: 0건 (통계 없는 테이블 없음)

-- 통계가 지나치게 오래된 테이블 확인 (7일 이상 경과)
SELECT OWNER, TABLE_NAME, NUM_ROWS, LAST_ANALYZED,
       ROUND(SYSDATE - LAST_ANALYZED) AS DAYS_OLD
FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED < SYSDATE - 7
ORDER BY DAYS_OLD DESC;
-- Cut-over 전 재수집 또는 소스 통계 재Import 검토
```

**인덱스 통계 완전성 확인**
```sql
-- 통계 없는 인덱스 0건 확인
SELECT OWNER, INDEX_NAME, TABLE_NAME, LAST_ANALYZED,
       NUM_ROWS, DISTINCT_KEYS, CLUSTERING_FACTOR
FROM DBA_IND_STATISTICS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED IS NULL
ORDER BY OWNER, TABLE_NAME;
-- 기대값: 0건

-- 인덱스 통계의 소스 대비 NUM_ROWS/DISTINCT_KEYS 비교 (샘플)
SELECT I.OWNER, I.INDEX_NAME, I.TABLE_NAME,
       S.NUM_ROWS, S.DISTINCT_KEYS, S.LAST_ANALYZED
FROM DBA_INDEXES I
JOIN DBA_IND_STATISTICS S ON S.OWNER=I.OWNER AND S.INDEX_NAME=I.INDEX_NAME
WHERE I.OWNER = '<SCHEMA>'
ORDER BY I.TABLE_NAME, I.INDEX_NAME;
```

**컬럼 통계 및 히스토그램 확인**
```sql
-- 컬럼 통계 없는 컬럼 확인 (핵심 테이블 대상)
SELECT OWNER, TABLE_NAME, COLUMN_NAME, NUM_DISTINCT, LAST_ANALYZED
FROM DBA_TAB_COL_STATISTICS
WHERE OWNER = '<SCHEMA>'
AND LAST_ANALYZED IS NULL
ORDER BY TABLE_NAME, COLUMN_NAME;

-- 히스토그램 보유 컬럼 비교 (소스/타겟)
SELECT OWNER, TABLE_NAME, COLUMN_NAME, HISTOGRAM, NUM_BUCKETS, LAST_ANALYZED
FROM DBA_TAB_COL_STATISTICS
WHERE OWNER = '<SCHEMA>'
AND HISTOGRAM != 'NONE'
ORDER BY TABLE_NAME, COLUMN_NAME;
-- 소스와 동일 컬럼에 히스토그램 존재하는지 확인
```

**통계 부족 시 조치**
```sql
-- 통계 없는 특정 테이블 즉시 수집
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname          => '<SCHEMA>',
        tabname          => '<TABLE_NAME>',
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        cascade          => TRUE,
        method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
        no_invalidate    => FALSE
    );
END;
/
```

### 6-6. Cut-over 직전 최종 오브젝트 완전성 확인

> **시점**: Cut-over D-Day, 소스 차단 직전 마지막 확인
> **목적**: GG 복제 기간 동안 소스에서 발생한 DDL 변경이 타겟에 모두 반영되었는지 확인

```sql
-- ① 최종 INVALID 객체 0건 확인 (Cut-over 진행 필수 조건)
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, OBJECT_TYPE;
-- ❌ INVALID 존재 시: 재컴파일 후 해결되지 않으면 No-Go

-- ② 최종 UNUSABLE 인덱스 0건 확인
SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS, PARTITIONED
FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- ❌ UNUSABLE 존재 시: REBUILD 후 해소되지 않으면 No-Go

-- ③ UNUSABLE 파티션 인덱스 0건 확인
SELECT INDEX_OWNER, INDEX_NAME, PARTITION_NAME, STATUS
FROM DBA_IND_PARTITIONS
WHERE STATUS != 'USABLE'
AND INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

-- ④ 오브젝트 유형별 COUNT — 소스와 타겟의 최종 비교
SELECT OBJECT_TYPE, COUNT(*) AS CNT
FROM DBA_OBJECTS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS',
                    'AUDSYS','CTXSYS','DBSFWUSER','DVSYS','GGSYS',
                    'GSMADMIN_INTERNAL','LBACSYS','OJVMSYS','WMSYS','XDB')
AND OBJECT_TYPE NOT IN ('JAVA CLASS','JAVA DATA','JAVA RESOURCE')
GROUP BY OBJECT_TYPE
ORDER BY OBJECT_TYPE;
-- 소스와 동일해야 함 (GG 복제 중 DDL로 생성된 오브젝트 포함)

-- ⑤ 통계 없는 테이블/인덱스 0건 최종 확인
SELECT COUNT(*) AS NO_STATS_TABLE FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED IS NULL;
-- 기대값: 0

SELECT COUNT(*) AS NO_STATS_INDEX FROM DBA_INDEXES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED IS NULL;
-- 기대값: 0

-- ⑥ 시퀀스 GAP 최종 확인 (GG Sequence 복제로 자동 갱신된 값 확인)
SELECT S.SEQUENCE_OWNER, S.SEQUENCE_NAME,
       S.LAST_NUMBER AS TARGET_LAST,
       S.CACHE_SIZE
FROM DBA_SEQUENCES S
WHERE S.SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY S.SEQUENCE_OWNER, S.SEQUENCE_NAME;
-- 타겟 LAST_NUMBER > 소스 현재값 이어야 함

-- ⑦ DISABLED 제약조건 확인 (FK는 의도적 DISABLE — Cut-over 후 ENABLE 예정)
SELECT OWNER, TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE, STATUS
FROM DBA_CONSTRAINTS
WHERE STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, CONSTRAINT_TYPE;
-- FK(R)는 Cut-over 시 ENABLE 예정 → 목록 확인
-- 나머지(P/U/C)는 기대값: 0건
```

### 6-7. 주의사항 체크 (05_Migration_Caution — 26항목)

| 구분 | 항목 | 확인 결과 |
|------|------|-----------|
| SE 제약 | ENABLE_GOLDENGATE_REPLICATION=TRUE | - |
| SE 제약 | PK 없는 테이블 ALL COLUMNS Supplemental Log | - |
| SE 제약 | Streams Pool 메모리 설정 | - |
| SE 제약 | DDL Replication 미지원 유형 식별 | - |
| SE 제약 | BITMAP Index → 일반 Index 대체 | - |
| SE 제약 | DBMS_JOB → DBMS_SCHEDULER 전환 | - |
| OCI GG | RDS Redo Log 보존 48h 이상 | - |
| OCI GG | Cloud 버전 DDL 제약 릴리즈 노트 확인 | - |
| OCI GG | Trail 저장소 비용/보존 정책 설정 | - |
| OCI GG | RDS→OCI 구간 Latency LAG 영향 측정 | - |
| OCI GG | Deployment 버전 호환성 | - |
| OCI GG | MV 수동 재생성 완료 | - |
| OCI GG | DB Link 수동 재생성 완료 | - |
| Cut-over | SCN 기반 동기화 준비 | - |
| Cut-over | Sequence 재설정 절차 확인 | - |
| Cut-over | Trigger 재활성화 스크립트 준비 | - |
| Cut-over | FK 재활성화 스크립트 준비 | - |
| Cut-over | JOB 활성화 절차 준비 | - |
| Cut-over | DB Link 전환 테스트 완료 | - |
| 상시운영 | LAG 알람 30초 이하 설정 | - |
| 상시운영 | Supplemental Logging 유지 절차 | - |
| 상시운영 | GGADMIN 비밀번호 만료 정책 | - |
| 상시운영 | Trail File 용량 임계치 알람 | - |
| 상시운영 | Discard 파일 일일 점검 체계 | - |
| 상시운영 | NLS 변경 금지 정책 수립 | - |
| 상시운영 | 신규 테이블 GG 포함 절차 | - |

### 6-8. Go/No-Go 판정 기준

| 판정 | 조건 |
|------|------|
| **Go** | 중요도 [상] 항목 전체 PASS, WARN 항목 원인 분석 완료 및 비즈니스 영향 없음 확인 |
| **Conditional Go** | WARN 항목 존재하나 조치 계획 수립 완료, 책임자 서명 |
| **No-Go** | 중요도 [상] 항목 1건 이상 FAIL |

---

## Phase 7: Cut-over

> **사전 조건**: Phase 6 Go/No-Go 판정 통과, 모든 팀 알림 완료, 롤백 절차 숙지

### 7-1. Cut-over 사전 체크리스트

- [ ] GG Extract LAG < 5초
- [ ] GG Replicat LAG < 5초
- [ ] Discard 파일 레코드 0건
- [ ] 검증 136항목 결과 집계 완료 (FAIL 0건)
- [ ] **타겟 INVALID 객체 0건** (Phase 6-6 최종 확인)
- [ ] **타겟 UNUSABLE 인덱스 0건** (Phase 6-6 최종 확인)
- [ ] **타겟 통계정보 존재 (LAST_ANALYZED IS NOT NULL)** 확인
- [ ] **오브젝트 유형별 소스/타겟 COUNT 일치** 확인
- [ ] 역방향 롤백 절차 확인 완료
- [ ] 애플리케이션 팀, DBA팀, 인프라팀 Cut-over 알림 완료
- [ ] 유지보수 공지 완료 (서비스 중단 예정 시간 30분)
- [ ] 소스 JOB BROKEN 스크립트 준비 완료
- [ ] Trigger ENABLE / FK ENABLE / Sequence 재설정 스크립트 준비 완료

### 7-2. Cut-over 실행 순서

```
Step 1. 소스 DB 애플리케이션 세션 차단
        - 앱 서버 다운 또는 소스 RDS 인바운드 1521 포트 차단
        - 잔여 세션 확인: SELECT COUNT(*) FROM V$SESSION WHERE TYPE='USER';

Step 2. 소스 DBMS_JOB BROKEN 처리 (이중 실행 방지)
        - 소스에서:
          SELECT 'EXEC DBMS_JOB.BROKEN(' || JOB || ', TRUE);'
          FROM DBA_JOBS WHERE BROKEN='N';
          -- 생성된 스크립트 실행

Step 3. 소스 CURRENT_SCN 최종 기록
        SELECT CURRENT_SCN, SYSDATE FROM V$DATABASE;
        -- 최종 SCN 기록 (예: 99887766)

Step 4. GG LAG = 0 확인 대기 (타임아웃: 30분)
        -- GGSCI에서 반복 실행
        LAG EXTRACT EXT1    -- 0초 목표
        LAG REPLICAT REP1   -- 0초 목표
        STATS REPLICAT REP1 TOTAL  -- 더 이상 카운트 증가 없음 확인

Step 5. Replicat 중지
        STOP REPLICAT REP1

Step 6. HANDLECOLLISIONS 제거 (소스 완전 차단 후 충돌 불가 → 불필요)
        EDIT PARAMS REP1   -- HANDLECOLLISIONS 라인 제거
        -- Replicat은 재기동하지 않음 (이미 중지됨)

Step 7. 타겟 DB 최종 데이터 검증
        -- 핵심 테이블 Row Count 확인
        -- 최신 데이터(MAX updated_date) 소스/타겟 비교

Step 8. Cut-over 완료 처리

  8a. Trigger 재활성화
      SELECT 'ALTER TRIGGER '||OWNER||'.'||TRIGGER_NAME||' ENABLE;'
      FROM DBA_TRIGGERS WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
      -- 생성 스크립트 실행

  8b. FK Constraint 일괄 재활성화
      SELECT 'ALTER TABLE '||OWNER||'.'||TABLE_NAME||
             ' ENABLE CONSTRAINT '||CONSTRAINT_NAME||';'
      FROM DBA_CONSTRAINTS
      WHERE CONSTRAINT_TYPE='R' AND STATUS='DISABLED'
      AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
      -- 생성 스크립트 실행 (에러 시 Orphan Row 제거 후 재시도)

  8c. Sequence 최종값 재설정 (GG 완전 중지 후 실행)
      STOP EXTRACT EXT1
      STOP EXTRACT PUMP1
      -- 소스 LAST_NUMBER + 여유분(예: CACHE_SIZE * 10)으로 재설정
      -- 안전한 방법:
      ALTER SEQUENCE <SCHEMA>.<SEQ_NAME> RESTART START WITH <SAFE_VALUE>;
      -- ※ RESTART START WITH 미지원 버전: INCREMENT BY 방식 사용 (값 정밀 계산 필수)

  8d. DBMS_SCHEDULER JOB 활성화 및 NEXT_RUN_DATE 재설정
      BEGIN
        DBMS_SCHEDULER.ENABLE(name => '<SCHEMA>.<JOB_NAME>');
      END;

  8e. DB Link 연결 전환 테스트
      SELECT * FROM DUAL@<DB_LINK_NAME>;
      -- 타겟 환경에서 원격 DB 접근 가능 여부 확인

Step 9. 애플리케이션 연결을 타겟 OCI DBCS로 전환
        - DNS 변경 또는 연결 문자열 전환
        - 앱 서버 기동

Step 10. 애플리케이션 정상 동작 확인
         - 핵심 기능 smoke test
         - 에러 로그 모니터링 (30분)
```

**[검증 `05_Migration_Caution #14~19`]** Cut-over 체크리스트 확인

### 7-3. Cut-over 후 즉시 검증

```sql
-- 1. 최신 데이터 확인 (소스 중단 직전 데이터가 타겟에 있는지)
SELECT MAX(<UPDATED_DATE_COL>) FROM <SCHEMA>.<KEY_TABLE>;

-- 2. Trigger 활성화 확인 (기대값: 0건 DISABLED)
SELECT COUNT(*) FROM DBA_TRIGGERS
WHERE STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

-- 3. FK 활성화 확인 (기대값: 0건 DISABLED)
SELECT COUNT(*) FROM DBA_CONSTRAINTS
WHERE STATUS = 'DISABLED' AND CONSTRAINT_TYPE = 'R'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

-- 4. Sequence 현재값 확인 (소스 MAX보다 크거나 같은지)
SELECT SEQUENCE_NAME, LAST_NUMBER FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER = '<SCHEMA>';

-- 5. DBMS_SCHEDULER JOB 활성화 확인 (기대값: 0건 DISABLED)
SELECT JOB_NAME, STATE, NEXT_RUN_DATE FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND STATE = 'DISABLED';

-- 6. INVALID 객체 최종 확인 (기대값: 0건)
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

-- 7. UNUSABLE 인덱스 최종 확인 (기대값: 0건)
SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS
FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

-- 8. 통계 있는 테이블 수 확인 (기대값: 통계 없는 테이블 0건)
SELECT COUNT(*) AS NO_STATS FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED IS NULL;
```

---

## Phase 8: Cut-over 후 안정화

### 8-1. 모니터링 체계 수립

**[검증 `01_GG_Process #26`]** LAG 임계치 알람 설정
- OCI GG Console → Monitoring → Alert 설정
  - Extract LAG > 30초: 경고
  - Replicat LAG > 30초: 경고
  - 프로세스 상태 ABEND: 즉시 알람

**[검증 `01_GG_Process #27`]** GGADMIN 비밀번호 만료 정책
```sql
-- 타겟 DBCS에서 GGADMIN 계정 패스워드 만료 정책 확인 및 설정
SELECT PROFILE FROM DBA_USERS WHERE USERNAME = 'GGADMIN';
SELECT RESOURCE_NAME, LIMIT FROM DBA_PROFILES
WHERE PROFILE = '<GGADMIN_PROFILE>'
AND RESOURCE_NAME = 'PASSWORD_LIFE_TIME';
-- 권장: UNLIMITED 또는 만료 전 갱신 알람 절차 수립
```

### 8-2. 상시 운영 Top 10 주의사항

| 순위 | 항목 | 조치 기준 |
|------|------|-----------|
| 1 | Extract/Replicat LAG 상시 모니터링 | LAG > 30초 즉시 알람 → 원인 분석 |
| 2 | PK 없는 테이블 ALL COLUMNS Logging 유지 | 신규 테이블 생성 시 즉시 적용 절차 수립 |
| 3 | Sequence GAP 누적 관리 | 주간 Gap 확인, 필요 시 재설정 |
| 4 | Trigger 이중 실행 방지 | GGADMIN 세션 대상 Trigger 예외 로직 확인 |
| 5 | DDL Replication ABEND 관리 | 미지원 DDL 수동 처리 절차 즉시 적용 |
| 6 | RDS Redo Log 보존 기간 관리 | 최소 24h 이상 유지 (Extract 장애 복구 대비) |
| 7 | GGADMIN 비밀번호 만료 모니터링 | 만료 30일 전 알람 → 즉시 갱신 |
| 8 | LOB 컬럼 Trail File 용량 급증 | Object Storage 80% 초과 시 알람 |
| 9 | Constraint DISABLED 상태 정기 점검 | 주간 점검 — Disabled 발견 시 원인 분석 후 ENABLE |
| 10 | NLS 파라미터/타임존 변경 금지 | 변경 금지 정책 문서화, 변경 시 승인 프로세스 |

### 8-3. Discard 파일 정기 점검

```
-- GGSCI
VIEW DISCARD REP1
-- 매일 1회 이상 확인
-- Discard 레코드 > 0건 시: 원인 분석 → 재적용 또는 데이터 수정 후 확인
```

### 8-4. 신규 테이블 GG 포함 절차

**[검증 `05_Migration_Caution #26`]** — GG 운영 중 신규 테이블 생성 시
1. 소스에서 신규 테이블 생성
2. 즉시 Supplemental Logging 추가: `ALTER TABLE <T> ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;`
3. GG Extract 파라미터에 TABLE 추가 (재기동 불필요 — 와일드카드 `TABLE <SCHEMA>.*;` 사용 시 자동 포함)
4. 타겟에도 동일 테이블 DDL 생성 (GG DDL 복제 또는 수동)
5. 복제 정상 여부 확인

### 8-5. 소스 DB 유지 및 종료 계획

- **D+1 ~ D+14**: 소스 RDS 유지 (롤백 대비)
- **D+7**: 타겟 안정화 확인 후 소스 → Read-Only 전환 검토
- **D+14**: 이상 없음 확인 시 소스 RDS 종료 및 비용 절감
- **최종**: OCI GG Deployment 종료 또는 상시 동기화 모드 유지 결정

---

## 롤백 계획

### 롤백 트리거 조건

| 조건 | 심각도 | 결정 타임아웃 |
|------|--------|-------------|
| 애플리케이션 심각한 기능 오류 | 즉시 | 30분 이내 결정 |
| 데이터 무결성 문제 발견 | 즉시 | 30분 이내 결정 |
| 타겟 DB 성능 임계치 초과 (소스 대비 30% 이상 저하) | 1시간 이내 | 1시간 |
| Cut-over 후 4시간 경과, 이슈 미해결 | 자동 롤백 결정 | — |

### 롤백 절차

```
Step 1. 타겟 DB 애플리케이션 즉시 차단

Step 2. 소스 RDS 상태 확인 (GG Supplemental Log 등 설정 유지 여부)
        SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;

Step 3. 역방향 GG 복제 검토 (사전에 구성되어 있는 경우)
        - 타겟 OCI DBCS → 소스 RDS 역방향 Extract/Replicat
        - Cut-over 이후 타겟에서 발생한 변경분을 소스로 역동기화
        - LAG = 0 확인 후 소스로 연결 전환

Step 4. 역방향 GG 미구성 시
        - Cut-over 이후 변경 데이터가 없다면 소스 RDS 그대로 사용 가능
        - 변경 데이터 있을 경우: 역방향 expdp/impdp 또는 수동 데이터 이관 검토

Step 5. 애플리케이션 연결을 소스 RDS로 복원
        - DNS 또는 연결 문자열 원복
        - 앱 서버 기동 및 정상 동작 확인

Step 6. 원인 분석 및 재마이그레이션 일정 수립
```

> **권장**: Cut-over 전에 역방향 GG Extract (타겟→소스)를 미리 구성해두면 롤백 시간을 최소화할 수 있음.
> 단, 역방향 복제는 소스 RDS의 GG 파라미터 및 추가 권한이 필요하므로 사전 테스트 필수.

---

## Dry Run (마이그레이션 리허설)

> **목적**: Cut-over 소요 시간 측정, 절차 오류 사전 발견
> **시기**: 실제 Cut-over D-7 (비업무 시간, 1~2시간)

### Dry Run 항목

- [ ] Phase 1 설정 적용 시간 측정
- [ ] expdp Export 소요 시간 측정 (DB 크기 기반 실제 측정)
- [ ] 네트워크 전송 속도 측정 (AWS → OCI Object Storage)
- [ ] impdp Import 소요 시간 측정
- [ ] GG Start → LAG 안정화 소요 시간 측정
- [ ] Cut-over Step 7~8 소요 시간 측정 (Trigger/FK ENABLE 등)
- [ ] 총 Cut-over 소요 시간 산정 → 서비스 중단 공지 시간 확정

---

## Validation 체크리스트 요약 (136항목)

> 검증 결과는 **OCI_GG_Validation_Plan_20260313.xlsx** 각 시트 결과(Result) 컬럼에 기록
> PASS / FAIL / WARN 중 하나로 기재

| Sheet | 영역 | 총 항목 | [상] 항목 | 비고 |
|-------|------|---------|-----------|------|
| 01_GG_Process | GG 프로세스 검증 | 28 | 18 | Pre-Check/Extract/Pump/Replicat/Trail |
| 02_Static_Schema | 정적 구조 검증 | 38 | 17 | 테이블/인덱스/제약/시퀀스/권한/INVALID 객체 |
| 03_Data_Validation | 데이터 정합성 검증 | 25 | 13 | RowCount/Checksum/LOB/NLS/참조무결성 |
| 04_Special_Objects | 특수 객체 검증 | 42 | 21 | MV/Trigger/DBLink/JOB/Sequence/파티션/DDL |
| 05_Migration_Caution | 주의사항 | 26 | 16 | SE제약/OCI GG/Cut-over/상시운영 |
| **합계** | | **159** | **85** | ※136(Excel기준)+23(추가항목) |
| **Excel 기준** | | **136** | | 04_Special_Objects 43항목 포함 |

> ※ Excel 06_Result_Dashboard 기준: GG 프로세스 28 + 정적 구조 38 + 데이터 정합성 27 + 특수 객체 43 = **136항목**

### 최종 Go/No-Go 기준

| 판정 | 조건 |
|------|------|
| **✅ Go** | 중요도 [상] 항목 전체 PASS + WARN 항목 원인 분석 완료 |
| **⚠️ Conditional Go** | WARN 항목 존재하나 비즈니스 영향 없음 확인 + 조치 계획 수립 + 책임자 서명 |
| **❌ No-Go** | 중요도 [상] 항목 1건 이상 FAIL — 즉시 조치 후 재검증 |

---

*작성: 마이그레이션 팀 | 검토: Review Agent (2026-03-17) | 승인: (서명)*
*참조: OCI_GG_Validation_Plan_20260313.xlsx*
