-------------------------------------------------------------------------------
-- step07_enable_gg.sql — GG 활성화 파라미터 (STEP 07)
-- 실행 환경: [소스]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 목적: Oracle SE에서 GoldenGate 사용을 위한 DB 파라미터 활성화
-- 담당: 소스 DBA
-- SE 제약: Oracle SE는 기본값 FALSE -- 반드시 수동 활성화 필요
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step07_enable_gg.log

PROMPT =============================================
PROMPT ENABLE_GOLDENGATE_REPLICATION 현재값 확인
PROMPT =============================================

SELECT NAME, VALUE FROM V$PARAMETER
WHERE NAME = 'enable_goldengate_replication';

PROMPT =============================================
PROMPT FALSE인 경우 활성화
PROMPT =============================================

-- [소스] FALSE인 경우 활성화
EXEC rdsadmin.rdsadmin_util.set_configuration('enable_goldengate_replication', 'true');

PROMPT =============================================
PROMPT 활성화 후 확인 -- DB 재기동 없이 즉시 적용됨
PROMPT 기대 결과: VALUE = TRUE
PROMPT =============================================

SELECT NAME, VALUE FROM V$PARAMETER
WHERE NAME = 'enable_goldengate_replication';

PROMPT =============================================
PROMPT STEP 07 GG 활성화 완료
PROMPT =============================================

SPOOL OFF
EXIT
