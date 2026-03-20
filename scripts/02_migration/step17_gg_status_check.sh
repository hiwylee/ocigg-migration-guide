#!/usr/bin/env bash
###############################################################################
# step17_gg_status_check.sh — GG 프로세스 상태 초기 확인
# 실행 환경: [GG]
# 목적: GG 복제 시작 후 30분 이내 초기 이상 여부 점검
# 담당: OCI GG 담당자
# 예상 소요: 30분
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step17_gg_status_check")
echo "=== STEP 17. GG 프로세스 상태 초기 확인 ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

###############################################################################
# 17-1. Extract 상태 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 17-1. Extract 상태 확인 ---" | tee -a "$LOG"

echo "
STATUS EXTRACT ${GG_EXTRACT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"
echo ">> 기대값: RUNNING" | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "Extract LAG 확인 (초기에는 LAG이 높을 수 있음 — 점차 감소 확인):" | tee -a "$LOG"
echo "
LAG EXTRACT ${GG_EXTRACT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "Extract DETAIL 확인 (Checkpoint SCN 증가 확인):" | tee -a "$LOG"
echo "
INFO EXTRACT ${GG_EXTRACT_NAME}, DETAIL
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "Extract Report 확인 (ABEND/ERROR 없음 확인):" | tee -a "$LOG"
echo "
VIEW REPORT ${GG_EXTRACT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

###############################################################################
# 17-2. Pump 상태 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 17-2. Pump 상태 확인 ---" | tee -a "$LOG"

echo "
STATUS EXTRACT ${GG_PUMP_NAME}
LAG EXTRACT ${GG_PUMP_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "Trail 파일 Object Storage로 정상 전송 확인:" | tee -a "$LOG"
echo "
INFO EXTRACT ${GG_PUMP_NAME}, SHOWCH
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

###############################################################################
# 17-3. Replicat 상태 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 17-3. Replicat 상태 확인 ---" | tee -a "$LOG"

echo "
STATUS REPLICAT ${GG_REPLICAT_NAME}
LAG REPLICAT ${GG_REPLICAT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "Replicat STATS 확인 (Insert/Update/Delete 건수 증가 확인):" | tee -a "$LOG"
echo "
STATS REPLICAT ${GG_REPLICAT_NAME} TOTAL
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "Replicat Report 확인 (ABEND/ERROR 없음, Discard 없음 확인):" | tee -a "$LOG"
echo "
VIEW REPORT ${GG_REPLICAT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

###############################################################################
# 17-4. Trail File 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 17-4. Trail File 확인 ---" | tee -a "$LOG"
echo "Trail 파일 생성 및 용량 증가 확인:" | tee -a "$LOG"
echo "LOB 복제 시 Trail 급증 주의 (Object Storage 임계치 알람 설정 권장)" | tee -a "$LOG"

echo "
INFO EXTRACT ${GG_EXTRACT_NAME}, SHOWCH
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

###############################################################################
# 17-5. Discard 파일 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 17-5. Discard 파일 확인 ---" | tee -a "$LOG"
echo "기대값: 레코드 0건" | tee -a "$LOG"
echo "Discard 있을 경우: 원인 분석 (중복 키, 참조 무결성 등)" | tee -a "$LOG"

echo "
VIEW DISCARD ${GG_REPLICAT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

###############################################################################
# 17-6. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 17-6. 결과 요약 ---" | tee -a "$LOG"
echo "  - ${GG_EXTRACT_NAME} 상태 RUNNING 확인" | tee -a "$LOG"
echo "  - ${GG_PUMP_NAME} 상태 RUNNING 확인" | tee -a "$LOG"
echo "  - ${GG_REPLICAT_NAME} 상태 RUNNING 확인" | tee -a "$LOG"
echo "  - Discard 파일 레코드 0건 확인" | tee -a "$LOG"
echo "  - ABEND/ERROR 없음 (VIEW REPORT) 확인" | tee -a "$LOG"
echo "  - Trail File 생성 및 증가 확인" | tee -a "$LOG"
echo "  - STATS REPLICAT — 건수 증가 확인" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 17 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
