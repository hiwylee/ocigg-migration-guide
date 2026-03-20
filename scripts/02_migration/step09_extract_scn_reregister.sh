#!/usr/bin/env bash
###############################################################################
# step09_extract_scn_reregister.sh — Extract SCN 기준점 재등록
# 실행 환경: [GG]
# 목적: expdp SCN을 기준으로 GG Extract가 해당 시점부터 추출을 시작하도록 설정
# 담당: OCI GG 담당자
# 예상 소요: 10분
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step09_extract_scn_reregister")
echo "=== STEP 09. Extract SCN 기준점 재등록 ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

###############################################################################
# SCN 값 입력 확인
###############################################################################
# STEP 08에서 기록한 FLASHBACK_SCN 값을 사용
if [ -z "${FLASHBACK_SCN:-}" ]; then
    echo "ERROR: FLASHBACK_SCN 환경변수가 설정되지 않았습니다." | tee -a "$LOG"
    echo "사용법: FLASHBACK_SCN=<SCN값> bash $0" | tee -a "$LOG"
    echo "예시:   FLASHBACK_SCN=98765432 bash $0" | tee -a "$LOG"
    exit 1
fi

echo "FLASHBACK_SCN: ${FLASHBACK_SCN}" | tee -a "$LOG"

###############################################################################
# 9-1. 기존 Extract 삭제 후 SCN 지정하여 재등록
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 9-1. 기존 Extract 삭제 후 SCN 지정하여 재등록 ---" | tee -a "$LOG"

# 기존 EXT1 삭제 (STEP 04에서 등록한 것 — BEGIN NOW로 등록된 것)
echo "
STOP EXTRACT ${GG_EXTRACT_NAME}
DELETE EXTRACT ${GG_EXTRACT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo ">> 기존 Extract 삭제 완료 (이미 STOPPED이면 STOP 오류 무시)" | tee -a "$LOG"

# SCN을 지정하여 재등록
echo "" | tee -a "$LOG"
echo "SCN을 지정하여 Extract 재등록: BEGIN SCN ${FLASHBACK_SCN}" | tee -a "$LOG"

echo "
ADD EXTRACT ${GG_EXTRACT_NAME}, INTEGRATED TRANLOG, BEGIN SCN ${FLASHBACK_SCN}
ADD EXTTRAIL ./dirdat/aa, EXTRACT ${GG_EXTRACT_NAME}, MEGABYTES 500
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

###############################################################################
# 9-2. Extract SCN 기준점 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 9-2. Extract SCN 기준점 확인 ---" | tee -a "$LOG"

echo "
INFO EXTRACT ${GG_EXTRACT_NAME}, DETAIL
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo ">> 확인 사항: 'Begin SCN: ${FLASHBACK_SCN}' 표시 확인" | tee -a "$LOG"
echo ">> 상태: STOPPED (아직 START 하지 않음 — 정상)" | tee -a "$LOG"

###############################################################################
# 9-3. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 9-3. 결과 요약 ---" | tee -a "$LOG"
echo "  - Extract 재등록 SCN: ${FLASHBACK_SCN}" | tee -a "$LOG"
echo "  - INFO EXTRACT SCN 확인 완료" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 09 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
