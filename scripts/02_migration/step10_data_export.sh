#!/usr/bin/env bash
###############################################################################
# step10_data_export.sh — DATA_ONLY expdp Export
# 실행 환경: [소스]
# 목적: STEP 08에서 기록한 SCN을 기준으로 전체 DB 데이터를 Export
# 담당: 소스 DBA
# 예상 소요: DB 크기에 따라 수 시간 ~ 수십 시간
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step10_data_export")
echo "=== STEP 10. DATA_ONLY expdp Export 실행 ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

###############################################################################
# FLASHBACK_SCN 값 확인
###############################################################################
if [ -z "${FLASHBACK_SCN:-}" ]; then
    echo "ERROR: FLASHBACK_SCN 환경변수가 설정되지 않았습니다." | tee -a "$LOG"
    echo "사용법: FLASHBACK_SCN=<SCN값> bash $0" | tee -a "$LOG"
    echo "예시:   FLASHBACK_SCN=98765432 bash $0" | tee -a "$LOG"
    exit 1
fi

echo "FLASHBACK_SCN: ${FLASHBACK_SCN}" | tee -a "$LOG"

###############################################################################
# 10-1. Export Directory 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 10-1. Export Directory 확인 ---" | tee -a "$LOG"

${SRC_SQLPLUS_CONN} ${SRC_MIG_USER}/${SRC_MIG_PASS}@"${SRC_TNS}" <<'SQL_EOF' 2>&1 | tee -a "$LOG"
SET LINESIZE 200
SET PAGESIZE 50
SELECT DIRECTORY_NAME, DIRECTORY_PATH
FROM DBA_DIRECTORIES
WHERE DIRECTORY_NAME = 'DATA_PUMP_DIR';
-- RDS 기본 경로: /rdsdbdata/userdirs/01/
EXIT;
SQL_EOF

###############################################################################
# 10-2. expdp DATA_ONLY 실행
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 10-2. expdp DATA_ONLY 실행 ---" | tee -a "$LOG"
echo "PARALLEL 주의사항: Oracle SE에서 PARALLEL 파라미터 효과가 제한적. PARALLEL=1로 시작하고 성능 확인 후 조정." | tee -a "$LOG"

# 백그라운드 실행 (tmux/screen 세션에서 실행 권장)
echo "expdp 시작..." | tee -a "$LOG"
nohup expdp ${SRC_MIG_USER}/${SRC_MIG_PASS}@"${SRC_TNS}" \
    FULL=Y \
    CONTENT=DATA_ONLY \
    FLASHBACK_SCN=${FLASHBACK_SCN} \
    DUMPFILE=fulldata_%U.dmp \
    FILESIZE=10G \
    PARALLEL=1 \
    LOGFILE=fulldata_export.log \
    EXCLUDE=STATISTICS \
    DIRECTORY=${EXPDP_DIR} \
> /tmp/expdp_run.log 2>&1 &

EXPDP_PID=$!
echo "expdp PID: ${EXPDP_PID}" | tee -a "$LOG"
echo "expdp PID: ${EXPDP_PID}" > /tmp/expdp_pid.txt

echo "" | tee -a "$LOG"
echo ">>> expdp가 백그라운드로 시작되었습니다." | tee -a "$LOG"
echo ">>> 아래 명령으로 진행 상태를 모니터링하세요." | tee -a "$LOG"

###############################################################################
# 10-3. Export 진행 모니터링 (안내)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 10-3. Export 진행 모니터링 ---" | tee -a "$LOG"
echo "별도 세션에서 주기적 확인:" | tee -a "$LOG"
echo "  tail -f ${EXPDP_DUMP_PATH}/fulldata_export.log" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "sqlplus에서 진행 상태 확인:" | tee -a "$LOG"
echo "  SELECT JOB_NAME, STATE, DEGREE, PERCENT_DONE" | tee -a "$LOG"
echo "  FROM DBA_DATAPUMP_JOBS" | tee -a "$LOG"
echo "  WHERE STATE != 'NOT RUNNING';" | tee -a "$LOG"

###############################################################################
# 10-4. Export 완료 확인 (안내)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 10-4. Export 완료 확인 (수동 확인 필요) ---" | tee -a "$LOG"
echo "Export 로그 마지막 줄 확인:" | tee -a "$LOG"
echo "  tail -50 ${EXPDP_DUMP_PATH}/fulldata_export.log" | tee -a "$LOG"
echo "기대값: 'Job \"MIGRATION_USER\".\"SYS_EXPORT_FULL_...\" successfully completed'" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "Export된 Dump 파일 목록 및 크기 확인:" | tee -a "$LOG"
echo "  ls -lh ${EXPDP_DUMP_PATH}/fulldata_*.dmp" | tee -a "$LOG"

###############################################################################
# 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 10-5. 결과 요약 ---" | tee -a "$LOG"
echo "  - expdp 오류 0건 확인 필요" | tee -a "$LOG"
echo "  - 'successfully completed' 메시지 확인 필요" | tee -a "$LOG"
echo "  - FLASHBACK_SCN=${FLASHBACK_SCN} 사용 확인" | tee -a "$LOG"
echo "  - Dump 파일 크기 확인 (예상 크기와 대비)" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "허용 가능한 오류:" | tee -a "$LOG"
echo "  ORA-39166 (오브젝트 미발견 — 삭제된 임시 오브젝트)" | tee -a "$LOG"
echo "  ORA-31693 (일부 오브젝트 Export 실패 — 원인 분석 필요)" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 10 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
