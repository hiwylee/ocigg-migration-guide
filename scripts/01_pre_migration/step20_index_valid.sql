-------------------------------------------------------------------------------
-- step20_index_valid.sql — 인덱스 VALID 상태 확인 (STEP 20)
-- 실행 환경: [타겟]
-- 접속 정보: ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS}
-- 목적: impdp 후 UNUSABLE 상태 인덱스 발견 및 REBUILD
-- 담당: 타겟 DBA
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step20_index_valid.log

PROMPT =============================================
PROMPT UNUSABLE 일반 인덱스 확인
PROMPT 기대값: 0건
PROMPT =============================================

SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS, PARTITIONED
FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);

PROMPT =============================================
PROMPT UNUSABLE 파티션 인덱스 확인
PROMPT 기대값: 0건
PROMPT =============================================

SELECT INDEX_OWNER, INDEX_NAME, PARTITION_NAME, STATUS
FROM DBA_IND_PARTITIONS
WHERE STATUS != 'USABLE'
AND INDEX_OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);

PROMPT =============================================
PROMPT UNUSABLE 인덱스 REBUILD 참고 (발견 시)
PROMPT   일반 인덱스: ALTER INDEX <OWNER>.<INDEX_NAME> REBUILD ONLINE;
PROMPT   파티션 인덱스: ALTER INDEX <OWNER>.<INDEX_NAME> REBUILD PARTITION <PARTITION_NAME> ONLINE;
PROMPT =============================================

-- REBUILD 후 재확인 (기대값: 0건)
SELECT COUNT(*) AS UNUSABLE_CNT FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);

PROMPT =============================================
PROMPT STEP 20 인덱스 VALID 상태 확인 완료
PROMPT =============================================

SPOOL OFF
EXIT
