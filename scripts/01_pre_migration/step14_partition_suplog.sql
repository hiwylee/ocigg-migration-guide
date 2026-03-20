-------------------------------------------------------------------------------
-- step14_partition_suplog.sql — 파티션 테이블 Supplemental Log (STEP 14)
-- 실행 환경: [소스]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 목적: 파티션 테이블도 GG 복제 시 Supplemental Log 필수 (OCI GG 특이사항)
-- 담당: 소스 DBA
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step14_partition_suplog.log

PROMPT =============================================
PROMPT 파티션 테이블 중 Supplemental Log 미적용 목록 확인
PROMPT 기대값: SUPLOG_STATUS = 'MISSING' 건수 = 0
PROMPT =============================================

SELECT PT.OWNER, PT.TABLE_NAME,
       CASE WHEN EXISTS (
           SELECT 1 FROM DBA_LOG_GROUPS LG
           WHERE LG.OWNER = PT.OWNER
           AND LG.LOG_GROUP_TABLE = PT.TABLE_NAME
       ) THEN 'OK' ELSE 'MISSING' END AS SUPLOG_STATUS
FROM DBA_PART_TABLES PT
WHERE PT.OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY PT.OWNER, PT.TABLE_NAME;

PROMPT =============================================
PROMPT MISSING 발견 시: PK가 없는 파티션 테이블이라면
PROMPT STEP 13과 동일하게 ALL COLUMNS 로깅 추가
PROMPT =============================================
PROMPT STEP 14 파티션 테이블 Supplemental Log 확인 완료
PROMPT =============================================

SPOOL OFF
EXIT
