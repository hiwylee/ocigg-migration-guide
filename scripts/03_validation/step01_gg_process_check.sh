#!/usr/bin/env bash
set -euo pipefail
###############################################################################
# step01_gg_process_check.sh — GG GGSCI 명령 검증 (STEP 01)
# 실행 환경: [GG]
# 목적: GG 프로세스(Extract/Pump/Replicat) 상태, LAG, Trail 검증
# 담당: OCI GG 담당자
# 예상 소요: 30분
# 참조: validation_plan.xlsx — 01_GG_Process (#10~28)
###############################################################################
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step01_gg_process_check")
echo "[$(timestamp)] STEP 01 GG 프로세스 GGSCI 검증 시작" | tee "${LOG}"

###############################################################################
# [1-2] Extract 상태 항목 (#10~14)
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[1-2] Extract 상태 항목 (#10~14)" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

# [검증항목 GG-010] Extract 상태 — 기대값: RUNNING
echo "" | tee -a "${LOG}"
echo "--- #10 Extract 상태 확인 ---" | tee -a "${LOG}"
echo "STATUS EXTRACT ${GG_EXTRACT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-011] Extract LAG — 기대값: < 30초
echo "" | tee -a "${LOG}"
echo "--- #11 Extract LAG 확인 ---" | tee -a "${LOG}"
echo "LAG EXTRACT ${GG_EXTRACT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-012] Extract Detail — Checkpoint SCN 지속 증가 확인
echo "" | tee -a "${LOG}"
echo "--- #12 Extract Detail 확인 ---" | tee -a "${LOG}"
echo "INFO EXTRACT ${GG_EXTRACT_NAME}, DETAIL" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-013] Extract Report — ABEND/ERROR 없음 확인
echo "" | tee -a "${LOG}"
echo "--- #13 Extract Report 확인 ---" | tee -a "${LOG}"
echo "VIEW REPORT ${GG_EXTRACT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-014] Extract Statistics
echo "" | tee -a "${LOG}"
echo "--- #14 Extract Statistics 확인 ---" | tee -a "${LOG}"
echo "STATS EXTRACT ${GG_EXTRACT_NAME} TOTAL" | ${GGSCI} 2>&1 | tee -a "${LOG}"

###############################################################################
# [1-3] Pump 상태 항목 (#15~17)
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[1-3] Pump 상태 항목 (#15~17)" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

# [검증항목 GG-015] Pump 상태 — 기대값: RUNNING
echo "" | tee -a "${LOG}"
echo "--- #15 Pump 상태 확인 ---" | tee -a "${LOG}"
echo "STATUS EXTRACT ${GG_PUMP_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-016] Pump LAG — 기대값: < 30초
echo "" | tee -a "${LOG}"
echo "--- #16 Pump LAG 확인 ---" | tee -a "${LOG}"
echo "LAG EXTRACT ${GG_PUMP_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-017] Pump Detail — OCI Object Storage Trail 정상 전송 확인
echo "" | tee -a "${LOG}"
echo "--- #17 Pump Detail 확인 ---" | tee -a "${LOG}"
echo "INFO EXTRACT ${GG_PUMP_NAME}, DETAIL" | ${GGSCI} 2>&1 | tee -a "${LOG}"

###############################################################################
# [1-4] Replicat 상태 항목 (#18~23)
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[1-4] Replicat 상태 항목 (#18~23)" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

# [검증항목 GG-018] Replicat 상태 — 기대값: RUNNING
echo "" | tee -a "${LOG}"
echo "--- #18 Replicat 상태 확인 ---" | tee -a "${LOG}"
echo "STATUS REPLICAT ${GG_REPLICAT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-019] Replicat LAG — 기대값: < 30초
echo "" | tee -a "${LOG}"
echo "--- #19 Replicat LAG 확인 ---" | tee -a "${LOG}"
echo "LAG REPLICAT ${GG_REPLICAT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-020] Replicat Statistics — Insert/Update/Delete 건수 증가 확인
echo "" | tee -a "${LOG}"
echo "--- #20 Replicat Statistics 확인 ---" | tee -a "${LOG}"
echo "STATS REPLICAT ${GG_REPLICAT_NAME} TOTAL" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-021] Replicat Report — ABEND/ERROR 없음 확인
echo "" | tee -a "${LOG}"
echo "--- #21 Replicat Report 확인 ---" | tee -a "${LOG}"
echo "VIEW REPORT ${GG_REPLICAT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-022] Discard 파일 — 기대값: 레코드 0건
echo "" | tee -a "${LOG}"
echo "--- #22 Replicat Discard 확인 ---" | tee -a "${LOG}"
echo "VIEW DISCARD ${GG_REPLICAT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-023] SUPPRESSTRIGGERS 적용 확인
echo "" | tee -a "${LOG}"
echo "--- #23 Replicat 파라미터 확인 (SUPPRESSTRIGGERS) ---" | tee -a "${LOG}"
echo "VIEW PARAMS ${GG_REPLICAT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

###############################################################################
# [1-5] Trail File 항목 (#24~25)
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[1-5] Trail File 항목 (#24~25)" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

# [검증항목 GG-024] Trail 용량 모니터링 (급증 없음 확인)
echo "" | tee -a "${LOG}"
echo "--- #24 Trail File Checkpoint 확인 ---" | tee -a "${LOG}"
echo "INFO EXTRACT ${GG_EXTRACT_NAME}, SHOWCH" | ${GGSCI} 2>&1 | tee -a "${LOG}"

# [검증항목 GG-025] LOB 복제 시 Trail 급증 주의
echo "" | tee -a "${LOG}"
echo "--- #25 Pump Trail Checkpoint 확인 ---" | tee -a "${LOG}"
echo "INFO EXTRACT ${GG_PUMP_NAME}, SHOWCH" | ${GGSCI} 2>&1 | tee -a "${LOG}"

###############################################################################
# [1-6] 상시운영 항목 (#26~28) — GGSCI 부분
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[1-6] 상시운영 항목 (#26~28)" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

# [검증항목 GG-026] LAG > 30초 알람 설정 확인
echo "" | tee -a "${LOG}"
echo "--- #26 LAG 알람 설정 확인 ---" | tee -a "${LOG}"
echo "[OCI콘솔] GoldenGate → Monitoring → Alarms 에서 수동 확인 필요" | tee -a "${LOG}"
echo "  - LAG > 30초 알람 설정 확인" | tee -a "${LOG}"
echo "  - ABEND 즉시 알람 설정 확인" | tee -a "${LOG}"
echo "  - 자동 업데이트(Auto Upgrade) 비활성화 확인" | tee -a "${LOG}"

# [검증항목 GG-027~028] SQL 부분은 step01_gg_process_check.sql 에서 실행

###############################################################################
# 네트워크 연결 테스트 (#9)
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[1-1] #9 네트워크 연결 테스트" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

echo "소스 DB 접속 테스트:" | tee -a "${LOG}"
${SRC_SQLPLUS_CONN} ${SRC_GG_USER}/${SRC_GG_PASS}@"${SRC_TNS}" <<'EOSQL' 2>&1 | tee -a "${LOG}"
SELECT 'CONNECTION_SUCCESS' AS RESULT FROM DUAL;
EXIT
EOSQL

echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[$(timestamp)] STEP 01 GG 프로세스 GGSCI 검증 완료" | tee -a "${LOG}"
echo "결과 로그: ${LOG}" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
