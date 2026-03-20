-------------------------------------------------------------------------------
-- step15_target_nls.sql — 타겟 NLS 파라미터 설정 (STEP 15)
-- 실행 환경: [타겟]
-- 접속 정보: ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS} AS SYSDBA
-- 목적: 소스와 동일한 NLS 환경을 타겟에 구성 (STEP 06에서 확인한 소스 값과 일치)
-- 담당: 타겟 DBA
-- 주의: <소스값> 을 STEP 06에서 확인한 실제 값으로 교체할 것
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step15_target_nls.log

PROMPT =============================================
PROMPT 소스에서 확인한 NLS 파라미터와 다른 항목 수정
PROMPT NLS_DATE_FORMAT, NLS_TIMESTAMP_FORMAT 등 SPFILE 설정
PROMPT ※ <소스값> 을 STEP 06에서 확인한 실제 값으로 교체
PROMPT =============================================

-- [타겟] 소스에서 확인한 NLS 파라미터와 다른 항목 수정
-- NLS_DATE_FORMAT, NLS_TIMESTAMP_FORMAT 등 SPFILE 설정
ALTER SYSTEM SET NLS_DATE_FORMAT      = '<소스값>' SCOPE=SPFILE;
ALTER SYSTEM SET NLS_TIMESTAMP_FORMAT = '<소스값>' SCOPE=SPFILE;

-- 변경 후 DB 재기동
SHUTDOWN IMMEDIATE;
STARTUP;

PROMPT =============================================
PROMPT 재기동 후 확인
PROMPT =============================================

SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN (
    'NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET',
    'NLS_DATE_FORMAT','NLS_TIMESTAMP_FORMAT','NLS_TIMESTAMP_TZ_FORMAT'
);

PROMPT =============================================
PROMPT STEP 15 타겟 NLS 파라미터 설정 완료
PROMPT =============================================

SPOOL OFF
EXIT
