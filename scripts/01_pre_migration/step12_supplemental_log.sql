-------------------------------------------------------------------------------
-- step12_supplemental_log.sql — Supplemental Logging 활성화 (STEP 12)
-- 실행 환경: [소스]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 목적: GG Extract가 Redo Log에서 변경 데이터를 추출하기 위한 최소 로깅 활성화
-- 담당: 소스 DBA
-- SE 제약: SE에서는 자동 활성화 안 됨 -- 수동 명령 필수
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step12_supplemental_log.log

PROMPT =============================================
PROMPT 현재 Supplemental Logging 상태 확인
PROMPT =============================================

SELECT SUPPLEMENTAL_LOG_DATA_MIN,
       SUPPLEMENTAL_LOG_DATA_PK,
       SUPPLEMENTAL_LOG_DATA_UI,
       SUPPLEMENTAL_LOG_DATA_FK,
       SUPPLEMENTAL_LOG_DATA_ALL
FROM V$DATABASE;

PROMPT =============================================
PROMPT 최소 Supplemental Logging 활성화 (서비스 중단 없음)
PROMPT =============================================

ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

PROMPT =============================================
PROMPT 활성화 확인
PROMPT 기대값: SUPPLEMENTAL_LOG_DATA_MIN = YES
PROMPT =============================================

SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;

PROMPT =============================================
PROMPT STEP 12 Supplemental Logging 활성화 완료
PROMPT =============================================

SPOOL OFF
EXIT
