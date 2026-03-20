/*
 * step14_post_import_check.sql — Import 후 오브젝트 상태 확인
 * 실행 환경: [타겟]
 * 목적: impdp DATA_ONLY 적재 후 INVALID 객체 및 UNUSABLE 인덱스 점검 및 해소
 * 담당: 타겟 DBA
 * 예상 소요: 30분 ~ 1시간
 *
 * 접속 정보 (env.sh 참조):
 *   sqlplus ${TGT_DBA_USER}/${TGT_DBA_PASS}@"${TGT_TNS}" AS SYSDBA
 *   또는 sqlplus ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}"
 */

WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK ON
SET SERVEROUTPUT ON

SPOOL logs/step14_post_import_check.log

PROMPT ============================================================================
PROMPT  STEP 14. Import 후 오브젝트 상태 확인
PROMPT ============================================================================

-- ============================================================================
-- 14-1. INVALID 객체 전수 확인
-- ============================================================================
PROMPT
PROMPT --- 14-1. INVALID 객체 전수 확인 ---

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

PROMPT
PROMPT INVALID 건수 기록: ______ 건

-- ============================================================================
-- 14-2. 전체 DB 재컴파일 (INVALID 존재 시)
-- ============================================================================
PROMPT
PROMPT --- 14-2. 전체 DB 재컴파일 (INVALID 존재 시) ---

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

PROMPT
PROMPT --- 재컴파일 후 재확인 ---

SELECT COUNT(*) AS STILL_INVALID
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);
-- 기대값: 0건

PROMPT
PROMPT 재컴파일 후에도 INVALID 잔존 시 개별 오브젝트 오류 확인:
PROMPT   ALTER PROCEDURE <OWNER>.<PROC_NAME> COMPILE;
PROMPT   SELECT * FROM USER_ERRORS;

-- ============================================================================
-- 14-3. 인덱스 UNUSABLE 확인
-- ============================================================================
PROMPT
PROMPT --- 14-3. 인덱스 UNUSABLE 확인 ---

PROMPT 전체 인덱스 상태 확인:
SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS, PARTITIONED
FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건

PROMPT
PROMPT 파티션 인덱스 파티션별 상태:
SELECT INDEX_OWNER, INDEX_NAME, PARTITION_NAME, STATUS
FROM DBA_IND_PARTITIONS
WHERE STATUS != 'USABLE'
AND INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건

PROMPT
PROMPT UNUSABLE 인덱스 발견 시 재빌드:
PROMPT   ALTER INDEX <OWNER>.<INDEX_NAME> REBUILD;
PROMPT   파티션 인덱스: ALTER INDEX <OWNER>.<INDEX_NAME> REBUILD PARTITION <PARTITION_NAME>;

-- ============================================================================
-- 14-4. 결과 요약
-- ============================================================================
PROMPT
PROMPT --- 14-4. 결과 요약 ---
PROMPT   - INVALID 객체 0건 (재컴파일 후) 확인
PROMPT   - UNUSABLE 인덱스 0건 (재빌드 후) 확인
PROMPT   - UNUSABLE 파티션 인덱스 0건 확인
PROMPT
PROMPT >> STEP 14 완료 서명: __________________ 일시: __________________

SPOOL OFF
EXIT;
