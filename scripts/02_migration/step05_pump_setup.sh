#!/usr/bin/env bash
###############################################################################
# step05_pump_setup.sh — Data Pump(PUMP1) 파라미터 및 등록
# 실행 환경: [GG]
# 목적: Extract Trail 파일을 OCI Object Storage의 Remote Trail로 전송하는 Pump 설정
# 담당: OCI GG 담당자
# 예상 소요: 20분
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step05_pump_setup")
echo "=== STEP 05. Data Pump (PUMP1) 파라미터 설정 및 등록 ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

###############################################################################
# 5-1. OCI Object Storage Trail 경로 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 5-1. OCI Object Storage Trail 경로 확인 ---" | tee -a "$LOG"
echo "[OCI콘솔] Object Storage → 버킷 목록" | tee -a "$LOG"
echo "  - Trail File 저장 버킷명 확인: ${OCI_BUCKET}" | tee -a "$LOG"
echo "  - OCI GG Trail 경로: oci://${OCI_BUCKET}@${OCI_NAMESPACE}/trail/rt" | tee -a "$LOG"

###############################################################################
# 5-2. Pump 등록 및 파라미터 작성
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 5-2. Pump 등록 및 파라미터 작성 ---" | tee -a "$LOG"

# Pump 프로세스 등록
echo "
ADD EXTRACT ${GG_PUMP_NAME}, EXTTRAILSOURCE ./dirdat/aa
ADD RMTTRAIL oci://${OCI_BUCKET}@${OCI_NAMESPACE}/trail/rt, EXTRACT ${GG_PUMP_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

# Pump 파라미터 내용
PUMP_PARAMS="EXTRACT ${GG_PUMP_NAME}
USERIDALIAS ggadmin_src DOMAIN OracleGoldenGate
RMTTRAIL oci://${OCI_BUCKET}@${OCI_NAMESPACE}/trail/rt
PASSTHRU

-- Extract와 동일한 범위 (PASSTHRU 모드에서는 와일드카드 사용)
TABLE *.*;
SEQUENCE *.*;"

echo "GGSCI에서 EDIT PARAMS ${GG_PUMP_NAME} 실행 후 아래 내용을 저장:" | tee -a "$LOG"
echo "${PUMP_PARAMS}" | tee -a "$LOG"

# GGSCI로 파라미터 파일 작성
echo "
EDIT PARAMS ${GG_PUMP_NAME}
${PUMP_PARAMS}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

###############################################################################
# 5-3. OCI Object Storage 연결 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 5-3. OCI Object Storage 연결 확인 ---" | tee -a "$LOG"
echo "OCI GG Deployment IAM Policy에서 Object Storage 접근 권한 부여 여부 확인" | tee -a "$LOG"

echo "
INFO EXTRACT ${GG_PUMP_NAME}, DETAIL
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo ">> Trail 저장소 경로 정상 등록 확인" | tee -a "$LOG"

###############################################################################
# 5-4. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 5-4. 결과 요약 ---" | tee -a "$LOG"
echo "  - ADD EXTRACT ${GG_PUMP_NAME} 등록 확인" | tee -a "$LOG"
echo "  - ADD RMTTRAIL Object Storage 경로 설정 확인" | tee -a "$LOG"
echo "  - PASSTHRU 파라미터 설정 확인" | tee -a "$LOG"
echo "  - Object Storage 접근 권한 (IAM Policy) 확인" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 05 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
