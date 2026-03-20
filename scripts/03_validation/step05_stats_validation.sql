-------------------------------------------------------------------------------
-- step05_stats_validation.sql — 통계정보 검증 (STEP 05)
-- 실행 환경: [타겟] / [양쪽] (히스토그램 비교 시)
-- 접속 정보: ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS} (타겟)
-- 목적: 타겟 DB의 모든 테이블/인덱스/컬럼에 유효한 통계정보가 존재하는지 확인
-- 담당: 타겟 DBA
-- 예상 소요: 30분
-- 참조: validation_plan.xlsx — 02_Static_Schema (#SS-36~38), 03_Data_Validation (#DV-21~25)
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step05_stats_validation.log

PROMPT =============================================
PROMPT STEP 05. 통계정보 검증
PROMPT =============================================

PROMPT
PROMPT =============================================
PROMPT [5-1] 테이블 통계 완전성 확인
PROMPT =============================================

PROMPT
PROMPT --- 통계 없는 테이블 0건 확인 ---
PROMPT [타겟] 실행
SELECT OWNER, TABLE_NAME, NUM_ROWS, BLOCKS, AVG_ROW_LEN, LAST_ANALYZED
FROM DBA_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL'
)
AND LAST_ANALYZED IS NULL
ORDER BY OWNER, TABLE_NAME;
-- 기대값: 0건

PROMPT
PROMPT --- 통계가 7일 이상 경과한 테이블 (Cut-over 전 재수집 검토) ---
PROMPT [타겟] 실행
SELECT OWNER, TABLE_NAME, LAST_ANALYZED,
       ROUND(SYSDATE - LAST_ANALYZED) AS DAYS_OLD
FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED < SYSDATE - 7
ORDER BY DAYS_OLD DESC;

PROMPT
PROMPT =============================================
PROMPT [5-2] 인덱스 통계 완전성 확인
PROMPT =============================================

PROMPT
PROMPT --- 통계 없는 인덱스 0건 확인 ---
PROMPT [타겟] 실행
SELECT OWNER, INDEX_NAME, TABLE_NAME, LAST_ANALYZED
FROM DBA_IND_STATISTICS
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
AND LAST_ANALYZED IS NULL
ORDER BY OWNER, TABLE_NAME;
-- 기대값: 0건

PROMPT
PROMPT =============================================
PROMPT [5-3] 컬럼 통계 및 히스토그램 확인
PROMPT =============================================

PROMPT
PROMPT --- 히스토그램 보유 컬럼 비교 (소스/타겟 동일 컬럼에 히스토그램 존재 여부) ---
PROMPT [양쪽] 실행 후 MINUS 비교
SELECT OWNER, TABLE_NAME, COLUMN_NAME, HISTOGRAM, NUM_BUCKETS, LAST_ANALYZED
FROM DBA_TAB_COL_STATISTICS
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
AND HISTOGRAM != 'NONE'
ORDER BY OWNER, TABLE_NAME, COLUMN_NAME;
-- 소스 MINUS 타겟 → 기대값: 0건 (동일 컬럼에 히스토그램 존재)

PROMPT
PROMPT =============================================
PROMPT [5-4] 통계 부족 시 즉시 수집
PROMPT =============================================

PROMPT
PROMPT --- 특정 테이블 통계 즉시 수집 (통계 없는 테이블 발견 시 수동 실행) ---
PROMPT [타겟] 아래 PL/SQL을 수동 실행
PROMPT
PROMPT 예시:
PROMPT BEGIN
PROMPT     DBMS_STATS.GATHER_TABLE_STATS(
PROMPT         ownname          => '<SCHEMA>',
PROMPT         tabname          => '<TABLE_NAME>',
PROMPT         estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
PROMPT         cascade          => TRUE,
PROMPT         method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
PROMPT         no_invalidate    => FALSE
PROMPT     );
PROMPT END;
PROMPT /

PROMPT
PROMPT =============================================
PROMPT STEP 05 통계정보 검증 완료
PROMPT =============================================

SPOOL OFF
EXIT
