#!/usr/bin/env bash
###############################################################################
# step16_start_replication.sh — GG 복제 시작 (ATCSN)
# 실행 환경: [GG]
# 목적: expdp SCN 기준점부터 GG 복제를 시작하여 소스/타겟 동기화 개시
# 담당: OCI GG 담당자
# 예상 소요: 15분 (시작 확인까지)
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step16_start_replication")
echo "=== STEP 16. GG 복제 시작 (ATCSN) ===" | tee "$LOG"
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
# 16-1. Extract 시작 (SCN 기준점)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 16-1. Extract 시작 (SCN 기준점) ---" | tee -a "$LOG"
echo "ATCSN: 해당 SCN을 포함하는 트랜잭션부터 적용 (expdp 경계 데이터 누락 방지)" | tee -a "$LOG"
echo "※ AFTERCSN은 해당 SCN 이후부터 — expdp와 경계에서 데이터 누락 가능성 있음 → 사용 금지" | tee -a "$LOG"

echo "
START EXTRACT ${GG_EXTRACT_NAME} ATCSN ${FLASHBACK_SCN}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

# Extract 상태 확인
echo "" | tee -a "$LOG"
echo "Extract 상태 확인:" | tee -a "$LOG"
echo "
STATUS EXTRACT ${GG_EXTRACT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"
echo ">> 기대값: RUNNING" | tee -a "$LOG"

###############################################################################
# 16-2. Pump 시작
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 16-2. Pump 시작 ---" | tee -a "$LOG"

echo "
START EXTRACT ${GG_PUMP_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

# Pump 상태 확인
echo "" | tee -a "$LOG"
echo "Pump 상태 확인:" | tee -a "$LOG"
echo "
STATUS EXTRACT ${GG_PUMP_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"
echo ">> 기대값: RUNNING" | tee -a "$LOG"

###############################################################################
# 16-3. Replicat 시작 (HANDLECOLLISIONS 활성 상태로 시작)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 16-3. Replicat 시작 (HANDLECOLLISIONS 활성 상태로 시작) ---" | tee -a "$LOG"
echo "HANDLECOLLISIONS 파라미터가 REP1에 설정된 상태로 시작" | tee -a "$LOG"
echo "(impdp 데이터와 GG 복제 데이터 충돌 자동 처리)" | tee -a "$LOG"

echo "
START REPLICAT ${GG_REPLICAT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

# Replicat 상태 확인
echo "" | tee -a "$LOG"
echo "Replicat 상태 확인:" | tee -a "$LOG"
echo "
STATUS REPLICAT ${GG_REPLICAT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"
echo ">> 기대값: RUNNING" | tee -a "$LOG"

###############################################################################
# 16-4. 초기 상태 확인 (3개 프로세스 모두 RUNNING 확인)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 16-4. 초기 상태 확인 ---" | tee -a "$LOG"
echo "3개 프로세스 모두 RUNNING 확인:" | tee -a "$LOG"

echo "
INFO ALL
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "기대값:" | tee -a "$LOG"
echo "  Extract ${GG_EXTRACT_NAME}:  RUNNING" | tee -a "$LOG"
echo "  Extract ${GG_PUMP_NAME}: RUNNING" | tee -a "$LOG"
echo "  Replicat ${GG_REPLICAT_NAME}: RUNNING" | tee -a "$LOG"

###############################################################################
# 16-5. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 16-5. 결과 요약 ---" | tee -a "$LOG"
echo "  - ATCSN 값: ${FLASHBACK_SCN}" | tee -a "$LOG"
echo "  - ${GG_EXTRACT_NAME} 시작 확인" | tee -a "$LOG"
echo "  - ${GG_PUMP_NAME} 시작 확인" | tee -a "$LOG"
echo "  - ${GG_REPLICAT_NAME} 시작 확인" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 16 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
