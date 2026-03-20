-------------------------------------------------------------------------------
-- step11_streams_pool.sql — Streams Pool 메모리 설정 (STEP 11)
-- 실행 환경: [소스] + [AWS콘솔]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 목적: Oracle SE는 GG용 Streams Pool을 수동으로 설정해야 함 (자동 할당 안 됨)
-- 담당: 소스 DBA
-- SE 제약: SE에서 Streams Pool은 자동 SGA 관리 대상 아님 -- 반드시 수동 설정
-- 기준: >= 256 MB (권장 512 MB)
--
-- AWS 콘솔 설정 절차 (SQL로 수행 불가한 부분):
--   1. RDS -> 파라미터 그룹 -> 해당 DB의 파라미터 그룹 선택
--   2. streams_pool_size 검색 -> 값 입력
--      - 최소: 268435456 (256MB)
--      - 권장: 536870912 (512MB)
--   3. 변경 적용 -> DB 재기동 (Pending Reboot 발생)
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step11_streams_pool.log

PROMPT =============================================
PROMPT 현재 streams_pool_size 확인
PROMPT =============================================

SELECT NAME, VALUE/1024/1024 AS MB
FROM V$PARAMETER WHERE NAME = 'streams_pool_size';

PROMPT =============================================
PROMPT 재기동 후 확인 (AWS 콘솔에서 설정 변경 후 실행)
PROMPT 기대값: >= 256 MB
PROMPT =============================================

SELECT NAME, VALUE/1024/1024 AS MB
FROM V$PARAMETER WHERE NAME = 'streams_pool_size';

PROMPT =============================================
PROMPT STEP 11 Streams Pool 확인 완료
PROMPT =============================================

SPOOL OFF
EXIT
