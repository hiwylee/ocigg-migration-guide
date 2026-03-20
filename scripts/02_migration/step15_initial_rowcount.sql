/*
 * step15_initial_rowcount.sql — Import 후 초기 Row Count
 * 실행 환경: [소스] / [타겟]
 * 목적: expdp SCN 고정 기준으로 소스/타겟 Row Count 일치 여부 검증
 * 담당: 소스 DBA, 타겟 DBA
 * 예상 소요: 30분 ~ 1시간 (테이블 규모에 따라)
 *
 * 접속 정보 (env.sh 참조):
 *   [소스] sqlplus ${SRC_MIG_USER}/${SRC_MIG_PASS}@"${SRC_TNS}"
 *   [타겟] sqlplus ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}"
 *
 * 사용법: 소스와 타겟 각각에서 동일하게 실행 후 결과 비교
 */

WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 300
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON
SET SERVEROUTPUT ON

SPOOL logs/step15_rowcount_script.sql

-- ============================================================================
-- 15-1. 전체 테이블 Row Count 비교 스크립트 생성
-- ============================================================================
-- 핵심 테이블 대상 COUNT(*) 스크립트 생성

SELECT 'SELECT ''' || OWNER || '.' || TABLE_NAME || ''' AS TBL, COUNT(*) AS CNT FROM ' ||
       OWNER || '.' || TABLE_NAME || ';'
FROM DBA_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL',
    'GGADMIN','GGS_TEMP','MIGRATION_USER'
)
ORDER BY OWNER, TABLE_NAME;

SPOOL OFF

-- ============================================================================
-- 15-2. 생성된 Row Count 스크립트 실행
-- ============================================================================
SET LINESIZE 200
SET PAGESIZE 50
SET FEEDBACK ON
SET HEADING ON

SPOOL logs/step15_rowcount_result.log

PROMPT ============================================================================
PROMPT  STEP 15. Import 후 초기 Row Count 확인
PROMPT ============================================================================
PROMPT
PROMPT 기대값: FLASHBACK_SCN 시점 기준 DATA_ONLY import이므로 소스/타겟 COUNT 완전 일치
PROMPT

@/tmp/step15_rowcount_script.sql

PROMPT
PROMPT ============================================================================
PROMPT  결과 비교: 소스와 타겟의 /tmp/step15_rowcount_result.log 파일을 비교
PROMPT ============================================================================
PROMPT
PROMPT >> STEP 15 완료 서명: __________________ 일시: __________________

SPOOL OFF
EXIT;
