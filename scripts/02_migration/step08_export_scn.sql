/*
 * step08_export_scn.sql — expdp SCN 고정 및 기록
 * 실행 환경: [소스]
 * 목적: expdp DATA_ONLY Export의 기준 SCN을 결정하고 기록
 * 담당: 소스 DBA, OCI GG 담당자
 * 예상 소요: 10분
 *
 * 접속 정보 (env.sh 참조):
 *   sqlplus ${SRC_DBA_USER}/${SRC_DBA_PASS}@"${SRC_TNS}"
 *
 * 중요: 이 SCN이 expdp FLASHBACK_SCN 값과 GG Extract 시작점의 기준이 됨
 *       이 SCN 값은 STEP 09 (GG Extract SCN 재등록)와 STEP 10 (expdp FLASHBACK_SCN)에서 사용
 */

WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 200
SET PAGESIZE 50
SET FEEDBACK ON

SPOOL logs/step08_export_scn.log

PROMPT ============================================================================
PROMPT  STEP 08. expdp SCN 고정 및 Export SCN 기록
PROMPT ============================================================================

-- ============================================================================
-- 8-1. Export 직전 SCN 확인
-- ============================================================================
PROMPT
PROMPT --- 8-1. Export 직전 SCN 확인 ---
PROMPT expdp 실행 직전에 실행하여 FLASHBACK_SCN 값을 확정

SELECT CURRENT_SCN,
       TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS SNAPSHOT_TIME
FROM V$DATABASE;

PROMPT
PROMPT ============================================================================
PROMPT  SCN 기록 (반드시 수기 기록)
PROMPT ============================================================================
PROMPT
PROMPT   FLASHBACK_SCN  : ___________________________
PROMPT   SNAPSHOT_TIME  : ___________________________
PROMPT   소스 DB 호스트명 : ___________________________
PROMPT   기록자          : ___________________________
PROMPT   기록 일시       : ___________________________
PROMPT
PROMPT ============================================================================
PROMPT  이 SCN 값 사용처:
PROMPT    - STEP 09: GG Extract SCN 재등록 (ADD EXTRACT ... BEGIN SCN <SCN>)
PROMPT    - STEP 10: expdp FLASHBACK_SCN=<SCN>
PROMPT ============================================================================

PROMPT
PROMPT >> STEP 08 완료 서명: __________________ 일시: __________________

SPOOL OFF
EXIT;
