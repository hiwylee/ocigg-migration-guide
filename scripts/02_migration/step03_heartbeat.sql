/*
 * step03_heartbeat.sql — Heartbeat Table 추가/확인
 * 실행 환경: [GG] (GGSCI) / [소스] / [타겟]
 * 목적: GG End-to-End LAG를 정확히 측정하기 위한 Heartbeat 메커니즘 활성화
 * 담당: OCI GG 담당자
 * 예상 소요: 10분
 *
 * 접속 정보 (env.sh 참조):
 *   - 소스: SRC_GG_USER / SRC_GG_PASS @ SRC_TNS
 *   - 타겟: TGT_GG_USER / TGT_GG_PASS @ TGT_TNS
 *
 * GGSCI 명령 (쉘에서 실행):
 *   echo "ADD HEARTBEATTABLE" | $GGSCI
 *   echo "INFO HEARTBEATTABLE" | $GGSCI
 */

-- ============================================================================
-- 3-1. Heartbeat Table 생성 (GGSCI에서 실행)
-- ============================================================================
-- 아래 명령은 GGSCI에서 실행:
--   ADD HEARTBEATTABLE
-- GG가 소스/타겟 양쪽에 Heartbeat 테이블 자동 생성
-- GGADMIN 계정으로 소스/타겟 각각 테이블 생성 확인

-- ============================================================================
-- 3-2. Heartbeat Table 확인 (GGSCI에서 실행)
-- ============================================================================
-- 아래 명령은 GGSCI에서 실행:
--   INFO HEARTBEATTABLE
-- Heartbeat 테이블명 및 마지막 업데이트 시각 확인

-- ============================================================================
-- 3-3. [소스] Heartbeat 테이블 생성 확인
-- ============================================================================
-- sqlplus ${SRC_GG_USER}/${SRC_GG_PASS}@"${SRC_TNS}"

WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 200
SET PAGESIZE 50
SET FEEDBACK ON
SPOOL logs/step03_heartbeat_source.log

PROMPT === [소스] Heartbeat 테이블 생성 확인 ===
SELECT TABLE_NAME
FROM DBA_TABLES
WHERE OWNER = 'GGADMIN'
AND TABLE_NAME LIKE '%HEARTBEAT%';
-- 기대값: GGS_HEARTBEAT 또는 GGS_LAG_HEARTBEAT 등 1건 이상

SPOOL OFF

-- ============================================================================
-- 3-4. [타겟] Heartbeat 테이블 생성 확인
-- ============================================================================
-- sqlplus ${TGT_GG_USER}/${TGT_GG_PASS}@"${TGT_TNS}"

-- SPOOL logs/step03_heartbeat_target.log

-- PROMPT === [타겟] Heartbeat 테이블 생성 확인 ===
-- SELECT TABLE_NAME
-- FROM DBA_TABLES
-- WHERE OWNER = 'GGADMIN'
-- AND TABLE_NAME LIKE '%HEARTBEAT%';
-- 기대값: GGS_HEARTBEAT 또는 GGS_LAG_HEARTBEAT 등 1건 이상

-- SPOOL OFF

EXIT;
