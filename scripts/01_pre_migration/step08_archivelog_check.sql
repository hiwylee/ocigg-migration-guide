-------------------------------------------------------------------------------
-- step08_archivelog_check.sql — Archive Log 모드 확인 (STEP 08)
-- 실행 환경: [소스]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 목적: GG Extract는 Archive Log 모드 필수 -- 미설정 시 복제 불가
-- 담당: 소스 DBA
-- 참고: AWS RDS는 기본 ARCHIVELOG 모드. NOARCHIVELOG이면 RDS Multi-AZ 설정 확인 필요.
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step08_archivelog_check.log

PROMPT =============================================
PROMPT Archive Log 모드 확인
PROMPT 기대값: ARCHIVELOG
PROMPT =============================================

SELECT LOG_MODE FROM V$DATABASE;

PROMPT =============================================
PROMPT STEP 08 Archive Log 확인 완료
PROMPT =============================================

SPOOL OFF
EXIT
