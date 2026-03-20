#!/usr/bin/env bash
###############################################################################
# step12_disable_and_import.sh — FK/Trigger DISABLE + impdp Import
# 실행 환경: [타겟]
# 목적: 참조 무결성 오류 없이 데이터를 적재하기 위해 FK/Trigger를 비활성화 후 impdp 실행
# 담당: 타겟 DBA
# 예상 소요: DB 크기에 따라 수 시간 ~ 수십 시간
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step12_disable_and_import")
echo "=== STEP 12. 타겟 FK/Trigger DISABLE 및 impdp Import 실행 ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

###############################################################################
# 12-1. FK Constraint 비활성화
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 12-1. FK Constraint 비활성화 ---" | tee -a "$LOG"

# FK DISABLE 스크립트 생성 및 실행
${TGT_SQLPLUS_CONN} ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" <<'SQL_EOF' 2>&1 | tee -a "$LOG"
WHENEVER SQLERROR CONTINUE
SET LINESIZE 300
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON

SPOOL /tmp/disable_fk.sql
SELECT 'ALTER TABLE '||OWNER||'.'||TABLE_NAME||
       ' DISABLE CONSTRAINT '||CONSTRAINT_NAME||';'
FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL',
    'GGADMIN','GGS_TEMP','MIGRATION_USER'
)
ORDER BY OWNER, TABLE_NAME;
SPOOL OFF

-- FK DISABLE 스크립트 실행
@/tmp/disable_fk.sql
COMMIT;
EXIT;
SQL_EOF

# FK DISABLE 적용 건수 확인
echo "" | tee -a "$LOG"
echo "FK DISABLE 적용 건수 확인:" | tee -a "$LOG"
${TGT_SQLPLUS_CONN} ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" <<'SQL_EOF' 2>&1 | tee -a "$LOG"
SET LINESIZE 200
SET PAGESIZE 50
SET FEEDBACK ON

SELECT COUNT(*) AS DISABLED_FK_CNT
FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R'
AND STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 소스의 FK 제약 건수와 동일
EXIT;
SQL_EOF

###############################################################################
# 12-2. Trigger 비활성화
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 12-2. Trigger 비활성화 ---" | tee -a "$LOG"

# 01.pre_migration.md STEP 23에서 준비한 disable_triggers.sql 실행
echo "disable_triggers.sql 실행..." | tee -a "$LOG"
${TGT_SQLPLUS_CONN} ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" @/tmp/disable_triggers.sql 2>&1 | tee -a "$LOG"

# Trigger DISABLE 적용 확인
echo "" | tee -a "$LOG"
echo "Trigger DISABLE 적용 확인:" | tee -a "$LOG"
${TGT_SQLPLUS_CONN} ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" <<'SQL_EOF' 2>&1 | tee -a "$LOG"
SET LINESIZE 200
SET PAGESIZE 50
SET FEEDBACK ON

SELECT COUNT(*) AS ENABLED_TRIGGER_CNT
FROM DBA_TRIGGERS
WHERE STATUS = 'ENABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: 0건 (모든 Trigger DISABLED)
EXIT;
SQL_EOF

###############################################################################
# 12-3. impdp DATA_ONLY 실행
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 12-3. impdp DATA_ONLY 실행 ---" | tee -a "$LOG"

# Import Directory 확인
echo "Import Directory 확인:" | tee -a "$LOG"
${TGT_SQLPLUS_CONN} ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" <<'SQL_EOF' 2>&1 | tee -a "$LOG"
SET LINESIZE 200
SELECT DIRECTORY_NAME, DIRECTORY_PATH FROM DBA_DIRECTORIES WHERE DIRECTORY_NAME='DATA_PUMP_DIR';
EXIT;
SQL_EOF

echo "" | tee -a "$LOG"
echo "impdp 시작 (백그라운드)..." | tee -a "$LOG"
echo "TABLE_EXISTS_ACTION=TRUNCATE 주의사항:" | tee -a "$LOG"
echo "  - 타겟 테이블을 TRUNCATE 후 INSERT — FK가 이미 DISABLE되어 있어야 함 (12-1에서 완료)" | tee -a "$LOG"
echo "  - CONTENT=DATA_ONLY이므로 테이블 구조(DDL)는 변경하지 않음" | tee -a "$LOG"

# impdp 실행 (백그라운드)
nohup impdp ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" \
    FULL=Y \
    CONTENT=DATA_ONLY \
    DUMPFILE=fulldata_%U.dmp \
    PARALLEL=1 \
    LOGFILE=fulldata_import.log \
    TABLE_EXISTS_ACTION=TRUNCATE \
    DIRECTORY=${IMPDP_DIR} \
> /tmp/impdp_run.log 2>&1 &

IMPDP_PID=$!
echo "impdp PID: ${IMPDP_PID}" | tee -a "$LOG"
echo "impdp PID: ${IMPDP_PID}" > /tmp/impdp_pid.txt

###############################################################################
# 12-4. Import 진행 모니터링 (안내)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 12-4. Import 진행 모니터링 ---" | tee -a "$LOG"
echo "별도 세션에서 주기적 확인:" | tee -a "$LOG"
echo "  tail -f ${IMPDP_DUMP_PATH}/fulldata_import.log" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "sqlplus에서 진행 상태 확인:" | tee -a "$LOG"
echo "  SELECT JOB_NAME, STATE, DEGREE, PERCENT_DONE" | tee -a "$LOG"
echo "  FROM DBA_DATAPUMP_JOBS" | tee -a "$LOG"
echo "  WHERE STATE != 'NOT RUNNING';" | tee -a "$LOG"

###############################################################################
# 12-5. Import 완료 확인 (안내)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 12-5. Import 완료 확인 (수동 확인 필요) ---" | tee -a "$LOG"
echo "Import 로그 마지막 줄 확인:" | tee -a "$LOG"
echo "  tail -50 ${IMPDP_DUMP_PATH}/fulldata_import.log" | tee -a "$LOG"
echo "기대값: 'Job \"MIGRATION_USER\".\"SYS_IMPORT_FULL_...\" successfully completed'" | tee -a "$LOG"

###############################################################################
# 12-6. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 12-6. 결과 요약 ---" | tee -a "$LOG"
echo "  - FK DISABLE 완료 (모든 FK) 확인" | tee -a "$LOG"
echo "  - Trigger DISABLE 완료 (모든 Trigger) 확인" | tee -a "$LOG"
echo "  - impdp 오류 0건 확인 필요" | tee -a "$LOG"
echo "  - 'successfully completed' 메시지 확인 필요" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "허용 가능한 오류:" | tee -a "$LOG"
echo "  ORA-31684 (이미 존재하는 오브젝트 — DATA_ONLY이므로 무시 가능)" | tee -a "$LOG"
echo "  ORA-39083 (특정 오브젝트 생성 실패 — 원인 분석 필요)" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 12 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
