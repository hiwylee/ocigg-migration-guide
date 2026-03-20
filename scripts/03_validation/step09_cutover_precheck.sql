-------------------------------------------------------------------------------
-- step09_cutover_precheck.sql — Cut-over 사전 체크리스트 (STEP 09)
-- 실행 환경: [GG] / [소스] / [타겟]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS} (소스)
--            ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS} (타겟)
-- 목적: Cut-over 실행 직전 최종 조건 확인 및 팀 준비 상태 확인
-- 담당: 마이그레이션 리더
-- 예상 소요: 30분
-- 비고: GG LAG 확인은 step01_gg_process_check.sh 와 연계 실행
--       GGSCI 명령은 step10_cutover_execute.sh 에서 실행
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step09_cutover_precheck.log

PROMPT =============================================
PROMPT STEP 09. Cut-over 사전 체크리스트
PROMPT =============================================

PROMPT
PROMPT =============================================
PROMPT [9-1] GG 실시간 LAG 최종 확인
PROMPT =============================================
PROMPT
PROMPT GGSCI에서 아래 명령 실행 (Cut-over 직전 — LAG < 5초 목표):
PROMPT   LAG EXTRACT EXT1
PROMPT   LAG REPLICAT REP1
PROMPT   STATS REPLICAT REP1 TOTAL
PROMPT
PROMPT EXT1 LAG: __________ (목표: < 5초) 판정: PASS / FAIL
PROMPT REP1 LAG: __________ (목표: < 5초) 판정: PASS / FAIL
PROMPT Discard 레코드: __________ (목표: 0건) 판정: PASS / FAIL

PROMPT
PROMPT =============================================
PROMPT [9-2] Cut-over 준비 스크립트 확인
PROMPT =============================================
PROMPT
PROMPT 아래 스크립트 준비 상태를 확인하십시오:
PROMPT   - DBMS_JOB BROKEN 처리 스크립트: 준비완료 / 미완료
PROMPT   - Trigger ENABLE 스크립트 (enable_triggers.sql): 준비완료 / 미완료
PROMPT   - FK ENABLE 스크립트 (enable_fk.sql): 준비완료 / 미완료
PROMPT   - Sequence 재설정 스크립트: 준비완료 / 미완료
PROMPT   - DBMS_SCHEDULER ENABLE 스크립트: 준비완료 / 미완료
PROMPT   - DNS/연결 문자열 전환 절차: 준비완료 / 미완료
PROMPT   - 롤백 절차 숙지 여부: 완료 / 미완료

PROMPT
PROMPT =============================================
PROMPT [9-3] 소스 DB 현재 세션 상태 확인
PROMPT =============================================

PROMPT
PROMPT --- 현재 활성 사용자 세션 확인 ---
PROMPT [소스] 실행
SELECT USERNAME, STATUS, COUNT(*) AS SESSION_CNT
FROM V$SESSION
WHERE TYPE = 'USER'
AND USERNAME IS NOT NULL
GROUP BY USERNAME, STATUS
ORDER BY USERNAME;

PROMPT
PROMPT --- GGADMIN 외 활성 세션 수 ---
PROMPT [소스] 실행
SELECT COUNT(*) AS NON_GG_SESSION_CNT
FROM V$SESSION
WHERE TYPE = 'USER'
AND USERNAME != 'GGADMIN'
AND USERNAME IS NOT NULL;
-- Cut-over 시작 전 이 값이 0에 가까워야 함

PROMPT
PROMPT =============================================
PROMPT [9-4] 타겟 DB 상태 사전 확인
PROMPT =============================================

PROMPT
PROMPT --- 타겟 DB 가동 상태 ---
PROMPT [타겟] 실행
SELECT INSTANCE_NAME, STATUS, DATABASE_STATUS FROM V$INSTANCE;

PROMPT
PROMPT --- 타겟 Tablespace 여유 공간 확인 ---
PROMPT [타겟] 실행
SELECT TABLESPACE_NAME,
       ROUND(SUM(BYTES)/1024/1024/1024, 2) AS TOTAL_GB,
       ROUND(SUM(BYTES - NVL(FREE_BYTES,0))/1024/1024/1024, 2) AS USED_GB,
       ROUND(SUM(NVL(FREE_BYTES,0))/1024/1024/1024, 2) AS FREE_GB,
       ROUND(SUM(NVL(FREE_BYTES,0))/SUM(BYTES)*100, 1) AS FREE_PCT
FROM (
    SELECT D.TABLESPACE_NAME, D.BYTES,
           F.FREE_BYTES
    FROM (SELECT TABLESPACE_NAME, SUM(BYTES) AS BYTES FROM DBA_DATA_FILES GROUP BY TABLESPACE_NAME) D
    LEFT JOIN (SELECT TABLESPACE_NAME, SUM(BYTES) AS FREE_BYTES FROM DBA_FREE_SPACE GROUP BY TABLESPACE_NAME) F
    ON D.TABLESPACE_NAME = F.TABLESPACE_NAME
)
GROUP BY TABLESPACE_NAME
ORDER BY FREE_PCT;

PROMPT
PROMPT =============================================
PROMPT STEP 09 Cut-over 사전 체크리스트 완료
PROMPT =============================================

SPOOL OFF
EXIT
