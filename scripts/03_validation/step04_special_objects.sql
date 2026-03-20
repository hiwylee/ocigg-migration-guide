-------------------------------------------------------------------------------
-- step04_special_objects.sql — 특수 객체 검증 (STEP 04, 42항목)
-- 실행 환경: [양쪽] / [타겟]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS} (소스)
--            ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS} (타겟)
-- 목적: MV, Trigger, DB Link, DBMS_JOB/SCHEDULER, Sequence, 파티션, DDL Replication 검증
-- 담당: 소스/타겟 DBA, OCI GG 담당자
-- 예상 소요: 2시간
-- 참조: validation_plan.xlsx — 04_Special_Objects (42항목)
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step04_special_objects.log

PROMPT =============================================
PROMPT STEP 04. 특수 객체 검증 (04_Special_Objects — 42항목)
PROMPT =============================================

PROMPT
PROMPT =============================================
PROMPT [4-1] MV (Materialized View) 검증 (#1~8)
PROMPT =============================================

-- [검증항목 SO-001~008] MV 검증
PROMPT
PROMPT --- MV 목록 및 속성 비교 ---
PROMPT [양쪽] 실행 후 MINUS 비교
SELECT OWNER, MVIEW_NAME, REFRESH_METHOD, REFRESH_MODE, STALENESS, BUILD_MODE, REWRITE_ENABLED
FROM DBA_MVIEWS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, MVIEW_NAME;
-- 소스 MINUS 타겟 → 기대값: 0건

PROMPT
PROMPT --- MV STALENESS 확인 ---
PROMPT [타겟] 실행
SELECT OWNER, MVIEW_NAME, STALENESS FROM DBA_MVIEWS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- FRESH 또는 NEEDS_COMPILE 이외의 값 주의

PROMPT
PROMPT --- MV Row Count 확인 ---
PROMPT [타겟] 아래 템플릿을 MV별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT COUNT(*) FROM <SCHEMA>.<MV_NAME>;

PROMPT
PROMPT --- MV REFRESH 동작 테스트 ---
PROMPT [타겟] 아래 PL/SQL을 MV별로 수동 실행
PROMPT
PROMPT 예시:
PROMPT BEGIN
PROMPT     DBMS_MVIEW.REFRESH('<SCHEMA>.<MV_NAME>', 'C');
PROMPT END;
PROMPT /
PROMPT -- REFRESH 후 오류 없음 확인, STALENESS = 'FRESH' 확인

PROMPT
PROMPT =============================================
PROMPT [4-2] Trigger 검증 (#9~15)
PROMPT =============================================

-- [검증항목 SO-009~015] Trigger 검증
PROMPT
PROMPT --- Trigger 목록 및 유형 비교 ---
PROMPT [양쪽] 실행 후 MINUS 비교
SELECT OWNER, TRIGGER_NAME, TRIGGER_TYPE, TRIGGERING_EVENT,
       TABLE_OWNER, TABLE_NAME, STATUS
FROM DBA_TRIGGERS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME, TRIGGER_NAME;
-- 소스 MINUS 타겟 → 기대값: 0건

PROMPT
PROMPT --- 현재 Trigger DISABLED 상태 확인 ---
PROMPT [타겟] 복제 중 — 기대값: 모두 DISABLED
SELECT OWNER, TRIGGER_NAME, STATUS FROM DBA_TRIGGERS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
AND STATUS = 'ENABLED';
-- 기대값: 0건 (복제 중에는 모두 DISABLED — Cut-over 후 ENABLE 예정)

PROMPT
PROMPT =============================================
PROMPT [4-3] DB Link 검증 (#16~22)
PROMPT =============================================

-- [검증항목 SO-016~022] DB Link 검증
PROMPT
PROMPT --- DB Link 목록 비교 ---
PROMPT [양쪽] 실행 후 비교
SELECT OWNER, DB_LINK, USERNAME, HOST FROM DBA_DB_LINKS
ORDER BY OWNER, DB_LINK;

PROMPT
PROMPT --- DB Link 연결 테스트 ---
PROMPT [타겟] 아래 템플릿을 DB Link별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT * FROM DUAL@<DB_LINK_NAME>;
PROMPT -- 기대값: DUMMY = 'X'

PROMPT
PROMPT --- DB Link 의존 객체 컴파일 상태 ---
PROMPT [타겟] 실행
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OBJECT_NAME IN (
    SELECT DISTINCT NAME FROM DBA_DEPENDENCIES
    WHERE REFERENCED_TYPE = 'DATABASE LINK'
)
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- 기대값: 0건

PROMPT
PROMPT =============================================
PROMPT [4-4] DBMS_JOB / DBMS_SCHEDULER 검증 (#23~29)
PROMPT =============================================

-- [검증항목 SO-023~029] DBMS_JOB / DBMS_SCHEDULER 검증
PROMPT
PROMPT --- 소스 DBMS_JOB 목록 (BROKEN 처리 여부 확인) ---
PROMPT [소스] 실행
SELECT JOB, LOG_USER, WHAT, INTERVAL, BROKEN, NEXT_DATE FROM DBA_JOBS
ORDER BY JOB;
-- 기대값: 모두 BROKEN = 'Y' (마이그레이션 중 이중 실행 방지)

PROMPT
PROMPT --- 타겟 DBMS_SCHEDULER JOB 확인 ---
PROMPT [타겟] 실행
SELECT JOB_NAME, OWNER, STATE, LAST_RUN_DURATION, NEXT_RUN_DATE, REPEAT_INTERVAL
FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, JOB_NAME;
-- 소스 JOB WHAT ↔ 타겟 JOB 매핑 확인

PROMPT
PROMPT --- 실행 주기(INTERVAL) 소스와 동일 여부 확인 ---
PROMPT [타겟] 실행
SELECT JOB_NAME, REPEAT_INTERVAL FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

PROMPT
PROMPT =============================================
PROMPT [4-5] Sequence 검증 (#30~33)
PROMPT =============================================

-- [검증항목 SO-030~033] Sequence 검증
PROMPT
PROMPT --- 소스 Sequence 현재값 + 필요 최솟값 계산 ---
PROMPT [소스] 실행
SELECT SEQUENCE_OWNER, SEQUENCE_NAME, LAST_NUMBER, CACHE_SIZE,
       LAST_NUMBER + CACHE_SIZE AS REQUIRED_MIN_TARGET
FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY SEQUENCE_OWNER, SEQUENCE_NAME;

PROMPT
PROMPT --- 타겟 Sequence LAST_NUMBER 확인 ---
PROMPT [타겟] 실행
SELECT SEQUENCE_OWNER, SEQUENCE_NAME, LAST_NUMBER, CACHE_SIZE
FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY SEQUENCE_OWNER, SEQUENCE_NAME;
-- 타겟 LAST_NUMBER > 소스 REQUIRED_MIN_TARGET 확인

PROMPT
PROMPT =============================================
PROMPT [4-6] 파티션 테이블 검증 (#34~38)
PROMPT =============================================

-- [검증항목 SO-034~038] 파티션 테이블 검증
PROMPT
PROMPT --- 파티션별 Row Count 비교 ---
PROMPT [양쪽] 실행 후 비교
SELECT OWNER, TABLE_NAME, PARTITION_NAME, NUM_ROWS, HIGH_VALUE
FROM DBA_TAB_PARTITIONS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME, PARTITION_POSITION;

PROMPT
PROMPT --- 파티션 Pruning 동작 확인 (실행계획 확인) ---
PROMPT [타겟] 아래 템플릿을 파티션 테이블별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT EXPLAIN PLAN FOR
PROMPT SELECT * FROM <SCHEMA>.<PARTITION_TABLE>
PROMPT WHERE <PARTITION_KEY> = <VALUE>;
PROMPT SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
PROMPT -- 기대값: "PARTITION RANGE SINGLE" 또는 특정 파티션만 접근

PROMPT
PROMPT =============================================
PROMPT [4-7] DDL Replication 검증 (#39~42)
PROMPT =============================================

-- [검증항목 SO-039~042] DDL Replication 검증
PROMPT
PROMPT --- DDL 복제 테스트 (테스트용 테이블로 진행) ---
PROMPT [소스] 테스트 테이블 생성
PROMPT CREATE TABLE MIGRATION_USER.GG_DDL_TEST (ID NUMBER, NAME VARCHAR2(100));
PROMPT
PROMPT [타겟] GG 복제 후 테이블 생성 여부 확인 (30초 대기)
PROMPT SELECT TABLE_NAME FROM DBA_TABLES WHERE OWNER = 'MIGRATION_USER' AND TABLE_NAME = 'GG_DDL_TEST';
PROMPT -- 기대값: GG_DDL_TEST 조회
PROMPT
PROMPT [소스] 컬럼 추가 DDL
PROMPT ALTER TABLE MIGRATION_USER.GG_DDL_TEST ADD (CREATED_DATE DATE);
PROMPT
PROMPT [타겟] 컬럼 추가 복제 확인
SELECT COLUMN_NAME FROM DBA_TAB_COLUMNS
WHERE OWNER = 'MIGRATION_USER' AND TABLE_NAME = 'GG_DDL_TEST'
ORDER BY COLUMN_ID;
PROMPT -- 기대값: ID, NAME, CREATED_DATE 3개 컬럼
PROMPT
PROMPT [소스] 테스트 테이블 정리
PROMPT DROP TABLE MIGRATION_USER.GG_DDL_TEST PURGE;
PROMPT
PROMPT ※ SE 환경에서 미지원 DDL 유형은 수동 처리 절차 문서화 필요

PROMPT
PROMPT =============================================
PROMPT STEP 04 특수 객체 검증 완료
PROMPT =============================================

SPOOL OFF
EXIT
