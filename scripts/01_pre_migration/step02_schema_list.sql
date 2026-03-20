-------------------------------------------------------------------------------
-- step02_schema_list.sql — 마이그레이션 대상 스키마 확정 (STEP 02)
-- 실행 환경: [소스]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 목적: 이전 대상 사용자 스키마 최종 목록 확정 및 관계자 공유
-- 담당: 마이그레이션 리더 + 소스 DBA
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step02_schema_list.log

PROMPT =============================================
PROMPT 이전 대상 사용자 스키마 최종 목록
PROMPT =============================================

SELECT USERNAME, ACCOUNT_STATUS, DEFAULT_TABLESPACE,
       CREATED, PROFILE
FROM DBA_USERS
WHERE USERNAME NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER',
    'GSMUSER','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
    'ORDPLUGINS','ORDSYS','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA',
    'SYS$UMF','SYSBACKUP','SYSDG','SYSKM','SYSRAC','WMSYS','XDB','XS$NULL',
    'GGADMIN','GGS_TEMP','MIGRATION_USER'
)
ORDER BY USERNAME;

PROMPT =============================================
PROMPT STEP 02 스키마 목록 확인 완료
PROMPT =============================================

SPOOL OFF
EXIT
