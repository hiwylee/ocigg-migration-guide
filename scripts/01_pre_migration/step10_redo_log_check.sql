-------------------------------------------------------------------------------
-- step10_redo_log_check.sql — Redo Log 그룹/크기 확인 (STEP 10)
-- 실행 환경: [소스]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 목적: Redo Log 스위치 빈발로 인한 Extract 성능 저하 방지
-- 담당: 소스 DBA
-- 기준: 그룹 수 >= 3, 그룹당 크기 >= 500MB
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step10_redo_log_check.log

PROMPT =============================================
PROMPT Redo Log 그룹/크기 확인
PROMPT 기준: 그룹 수 >= 3, 그룹당 크기 >= 500MB
PROMPT =============================================

SELECT GROUP#, MEMBERS, BYTES/1024/1024 AS MB, STATUS
FROM V$LOG
ORDER BY GROUP#;

PROMPT =============================================
PROMPT 기준 미달 시: 운영 중 Log Switch 빈도 모니터링 후
PROMPT LOB 복제 등 부하 고려하여 증설 검토
PROMPT =============================================
PROMPT STEP 10 Redo Log 확인 완료
PROMPT =============================================

SPOOL OFF
EXIT
