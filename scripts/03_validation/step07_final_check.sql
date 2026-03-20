-------------------------------------------------------------------------------
-- step07_final_check.sql — Cut-over 직전 최종 확인 (STEP 07)
-- 실행 환경: [양쪽] / [타겟]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS} (소스)
--            ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS} (타겟)
-- 목적: GG 복제 기간 중 소스에서 발생한 DDL 변경이 타겟에 모두 반영되었는지 최종 확인
-- 시점: Cut-over D-Day, 소스 차단 직전
-- 담당: 소스/타겟 DBA
-- 예상 소요: 30분
-- 참조: validation_plan.xlsx — 02_Static_Schema (#SS-01~38), 05_Migration_Caution (#MC-01~26)
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step07_final_check.log

PROMPT =============================================
PROMPT STEP 07. Cut-over 직전 최종 오브젝트 완전성 확인
PROMPT =============================================

PROMPT
PROMPT =============================================
PROMPT [7-1] 최종 INVALID 객체 0건 확인
PROMPT =============================================

PROMPT
PROMPT --- INVALID 객체 확인 ---
PROMPT [타겟] 실행 — 기대값: 0건 (Cut-over 진행 필수 조건)
SELECT OWNER, OBJECT_TYPE, OBJECT_NAME, STATUS
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, OBJECT_TYPE;

PROMPT
PROMPT =============================================
PROMPT [7-2] 최종 UNUSABLE 인덱스 0건 확인
PROMPT =============================================

PROMPT
PROMPT --- UNUSABLE 인덱스 확인 ---
PROMPT [타겟] 실행 — 기대값: 0건
SELECT OWNER, INDEX_NAME, TABLE_NAME, STATUS, PARTITIONED
FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT
PROMPT --- 파티션 인덱스 UNUSABLE 확인 ---
PROMPT [타겟] 실행
SELECT INDEX_OWNER, INDEX_NAME, PARTITION_NAME, STATUS
FROM DBA_IND_PARTITIONS
WHERE STATUS != 'USABLE'
AND INDEX_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT
PROMPT =============================================
PROMPT [7-3] 오브젝트 유형별 COUNT 최종 비교
PROMPT =============================================

PROMPT
PROMPT --- 오브젝트 유형별 COUNT ---
PROMPT [양쪽] 실행 — 소스/타겟 동일해야 함
SELECT OBJECT_TYPE, COUNT(*) AS CNT
FROM DBA_OBJECTS
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS','OJVMSYS','WMSYS','XDB'
)
AND OBJECT_TYPE NOT IN ('JAVA CLASS','JAVA DATA','JAVA RESOURCE')
GROUP BY OBJECT_TYPE
ORDER BY OBJECT_TYPE;

PROMPT
PROMPT =============================================
PROMPT [7-4] 통계 없는 테이블/인덱스 최종 확인
PROMPT =============================================

PROMPT
PROMPT --- 통계 없는 테이블 ---
PROMPT [타겟] 기대값: 0
SELECT COUNT(*) AS NO_STATS_TABLE FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED IS NULL;

PROMPT
PROMPT --- 통계 없는 인덱스 ---
PROMPT [타겟] 기대값: 0
SELECT COUNT(*) AS NO_STATS_INDEX FROM DBA_INDEXES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED IS NULL;

PROMPT
PROMPT =============================================
PROMPT [7-5] Sequence GAP 최종 확인
PROMPT =============================================

PROMPT
PROMPT --- 타겟 LAST_NUMBER > 소스 현재값 확인 ---
PROMPT [타겟] 실행
SELECT SEQUENCE_OWNER, SEQUENCE_NAME, LAST_NUMBER, CACHE_SIZE
FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY SEQUENCE_OWNER, SEQUENCE_NAME;

PROMPT
PROMPT =============================================
PROMPT STEP 07 Cut-over 직전 최종 확인 완료
PROMPT =============================================

SPOOL OFF
EXIT
