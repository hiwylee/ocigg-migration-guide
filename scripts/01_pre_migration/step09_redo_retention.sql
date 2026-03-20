-------------------------------------------------------------------------------
-- step09_redo_retention.sql — Redo Log 보존 기간 설정 (STEP 09)
-- 실행 환경: [소스]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 목적: Extract 장애 시 복구를 위한 최소 48시간 보존 설정
-- 담당: 소스 DBA
-- 중요: 기본값 1시간 -- Extract 지연 시 Archive Log 삭제되면 복구 불가
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step09_redo_retention.log

PROMPT =============================================
PROMPT 현재 보존 기간 확인
PROMPT =============================================

SELECT * FROM rdsadmin.rds_configuration
WHERE name = 'archivelog retention hours';

PROMPT =============================================
PROMPT 48시간으로 설정 (최소 24시간, 권장 48시간)
PROMPT =============================================

EXEC rdsadmin.rdsadmin_util.set_configuration('archivelog retention hours', 48);

PROMPT =============================================
PROMPT 적용 확인
PROMPT 기대값: >= 24
PROMPT =============================================

SELECT * FROM rdsadmin.rds_configuration
WHERE name = 'archivelog retention hours';

PROMPT =============================================
PROMPT STEP 09 Redo Log 보존 기간 설정 완료
PROMPT =============================================

SPOOL OFF
EXIT
