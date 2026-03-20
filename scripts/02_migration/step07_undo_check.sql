/*
 * step07_undo_check.sql — UNDO/Flashback 사전 확인
 * 실행 환경: [소스]
 * 목적: expdp FLASHBACK_SCN 사용 전 UNDO 충분성 검증
 * 담당: 소스 DBA
 * 예상 소요: 15분
 *
 * 접속 정보 (env.sh 참조):
 *   sqlplus ${SRC_DBA_USER}/${SRC_DBA_PASS}@"${SRC_TNS}"
 */

WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 200
SET PAGESIZE 50
SET FEEDBACK ON
SET SERVEROUTPUT ON

SPOOL logs/step07_undo_check.log

PROMPT ============================================================================
PROMPT  STEP 07. UNDO / Flashback 사전 확인
PROMPT ============================================================================

-- ============================================================================
-- 7-1. UNDO 파라미터 확인
-- ============================================================================
PROMPT
PROMPT --- 7-1. UNDO 파라미터 확인 ---
PROMPT UNDO_RETENTION 확인 (Export 예상 소요시간 + 여유분 이상이어야 함)

SELECT NAME, VALUE
FROM V$PARAMETER
WHERE NAME IN ('undo_retention', 'undo_tablespace');

PROMPT
PROMPT 판정 기준: undo_retention >= Export 소요시간(초) + 3600 이상
PROMPT undo_retention 부족 시: ALTER SYSTEM SET UNDO_RETENTION=<seconds> SCOPE=BOTH;
PROMPT AWS RDS에서 변경 제한될 경우: FLASHBACK_TIME 파라미터 사용 또는 야간 저부하 시간대 Export 권장

-- ============================================================================
-- 7-2. UNDO 테이블스페이스 여유 공간 확인
-- ============================================================================
PROMPT
PROMPT --- 7-2. UNDO 테이블스페이스 여유 공간 확인 ---

SELECT TABLESPACE_NAME,
       ROUND(SUM(BYTES)/1024/1024/1024, 2) AS FREE_GB
FROM DBA_FREE_SPACE
WHERE TABLESPACE_NAME LIKE '%UNDO%'
GROUP BY TABLESPACE_NAME;

PROMPT
PROMPT 판정 기준: DB 크기의 10% 이상

-- ============================================================================
-- 7-3. MIGRATION_USER Flashback 권한 확인
-- ============================================================================
PROMPT
PROMPT --- 7-3. MIGRATION_USER Flashback 권한 확인 ---

SELECT GRANTEE, PRIVILEGE
FROM DBA_SYS_PRIVS
WHERE GRANTEE = 'MIGRATION_USER'
AND PRIVILEGE IN ('FLASHBACK ANY TABLE', 'EXP_FULL_DATABASE');

PROMPT
PROMPT 기대값: FLASHBACK ANY TABLE, EXP_FULL_DATABASE 모두 조회

-- ============================================================================
-- 7-4. 결과 요약
-- ============================================================================
PROMPT
PROMPT --- 7-4. 결과 요약 ---
PROMPT   - UNDO_RETENTION >= 예상 Export 시간 + 여유분 확인
PROMPT   - UNDO 테이블스페이스 여유 공간 충분 확인
PROMPT   - MIGRATION_USER Flashback 권한 확인
PROMPT
PROMPT >> STEP 07 완료 서명: __________________ 일시: __________________

SPOOL OFF
EXIT;
