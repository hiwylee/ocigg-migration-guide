-------------------------------------------------------------------------------
-- step06_nls_check.sql — NLS/Timezone 소스-타겟 비교 (STEP 06)
-- 실행 환경: [소스] + [타겟]
-- 접속 정보 (소스): ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 접속 정보 (타겟): ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS}
-- 목적: 소스/타겟 NLS 설정 일치 여부 확인 -- 불일치 시 문자 깨짐 발생
-- 담당: 소스 DBA + 타겟 DBA
-- 주의: NLS_CHARACTERSET 불일치 발견 시 -> 즉시 마이그레이션 중단, 타겟 재생성
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step06_nls_check.log

PROMPT =============================================
PROMPT NLS 파라미터 조회
PROMPT ※ 소스/타겟 각각 접속하여 실행 후 결과 비교
PROMPT =============================================

-- [소스] / [타겟] NLS 파라미터 조회
SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN (
    'NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET',
    'NLS_DATE_FORMAT', 'NLS_TIMESTAMP_FORMAT',
    'NLS_TIMESTAMP_TZ_FORMAT', 'NLS_LANGUAGE',
    'NLS_TERRITORY', 'NLS_SORT', 'NLS_COMP'
)
ORDER BY PARAMETER;

PROMPT --- DBTIMEZONE 확인 ---

SELECT DBTIMEZONE FROM DUAL;

PROMPT =============================================
PROMPT 비교 기준:
PROMPT   NLS_CHARACTERSET, DBTIMEZONE 불일치 -> 즉시 중단, 타겟 재생성
PROMPT   나머지 파라미터 불일치 -> 타겟 SPFILE 수정 후 재기동
PROMPT =============================================
PROMPT STEP 06 NLS 확인 완료
PROMPT =============================================

SPOOL OFF
EXIT
