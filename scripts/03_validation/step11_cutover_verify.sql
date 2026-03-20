-------------------------------------------------------------------------------
-- step11_cutover_verify.sql — Cut-over 후 즉시 검증 (STEP 11)
-- 실행 환경: [타겟]
-- 접속 정보: ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS}
-- 목적: Cut-over 직후 타겟 DB 상태 이상 여부 즉시 점검
-- 담당: 타겟 DBA, 애플리케이션 담당
-- 예상 소요: 30분
-- 비고: FAIL 항목 발생 시 마이그레이션 리더에게 즉시 보고 → 30분 이내 롤백 여부 결정
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step11_cutover_verify.log

PROMPT =============================================
PROMPT STEP 11. Cut-over 후 즉시 검증
PROMPT =============================================

PROMPT
PROMPT =============================================
PROMPT [11-1] 데이터 최신성 확인
PROMPT =============================================

PROMPT
PROMPT --- 소스 차단 직전 데이터가 타겟에 있는지 확인 ---
PROMPT [타겟] 아래 템플릿을 핵심 테이블별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT MAX(<UPDATED_DATE_COL>) AS LATEST_DATA
PROMPT FROM <SCHEMA>.<KEY_TABLE>;
PROMPT -- 기대값: 소스 차단 시각과 동일하거나 직전

PROMPT
PROMPT =============================================
PROMPT [11-2] 오브젝트 상태 최종 확인
PROMPT =============================================

PROMPT
PROMPT --- Trigger 활성화 확인 ---
PROMPT [타겟] 기대값: 0건 DISABLED
SELECT COUNT(*) AS DISABLED_TRIGGER_CNT FROM DBA_TRIGGERS
WHERE STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT
PROMPT --- FK 활성화 확인 ---
PROMPT [타겟] 기대값: 0건 DISABLED
SELECT COUNT(*) AS DISABLED_FK_CNT FROM DBA_CONSTRAINTS
WHERE STATUS = 'DISABLED' AND CONSTRAINT_TYPE = 'R'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT
PROMPT --- Sequence 현재값 확인 (소스 최댓값보다 큰지) ---
PROMPT [타겟] 실행
SELECT SEQUENCE_OWNER, SEQUENCE_NAME, LAST_NUMBER
FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY SEQUENCE_OWNER, SEQUENCE_NAME;

PROMPT
PROMPT --- SCHEDULER JOB 활성화 확인 ---
PROMPT [타겟] 기대값: 0건
SELECT JOB_NAME, STATE FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND STATE = 'DISABLED';

PROMPT
PROMPT --- INVALID 객체 최종 확인 ---
PROMPT [타겟] 기대값: 0건
SELECT COUNT(*) AS INVALID_CNT FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT
PROMPT --- UNUSABLE 인덱스 최종 확인 ---
PROMPT [타겟] 기대값: 0건
SELECT COUNT(*) AS UNUSABLE_IDX_CNT FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT
PROMPT --- 통계 없는 테이블 최종 확인 ---
PROMPT [타겟] 기대값: 0건
SELECT COUNT(*) AS NO_STATS_CNT FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND LAST_ANALYZED IS NULL;

PROMPT
PROMPT =============================================
PROMPT [11-3] Cut-over 후 즉시 검증 결과 요약
PROMPT =============================================
PROMPT
PROMPT | 항목                              | 기대값              | 확인 결과 | 판정 |
PROMPT |-----------------------------------|--------------------|-----------| ---- |
PROMPT | 최신 데이터 확인                     | 소스 차단 시각 기준   |           |      |
PROMPT | DISABLED Trigger                   | 0건                |           |      |
PROMPT | DISABLED FK                        | 0건                |           |      |
PROMPT | Sequence 현재값 (소스 최댓값 이상)     | 정상               |           |      |
PROMPT | DISABLED SCHEDULER JOB             | 0건                |           |      |
PROMPT | INVALID 객체                       | 0건                |           |      |
PROMPT | UNUSABLE 인덱스                     | 0건                |           |      |
PROMPT | 통계 없는 테이블                     | 0건                |           |      |
PROMPT | Smoke Test 결과                    | PASS               |           |      |
PROMPT | 에러 로그 (30분간 모니터링)           | 오류 없음           |           |      |
PROMPT
PROMPT *** FAIL 항목 발생 시: 마이그레이션 리더에게 즉시 보고 → 30분 이내 롤백 여부 결정 ***

PROMPT
PROMPT =============================================
PROMPT STEP 11 Cut-over 후 즉시 검증 완료
PROMPT =============================================

SPOOL OFF
EXIT
