#!/usr/bin/env bash
###############################################################################
# step06_replicat_setup.sh — Replicat(REP1) 파라미터 및 등록
# 실행 환경: [GG]
# 목적: OCI Object Storage Trail을 읽어 타겟 DBCS에 변경 데이터를 적용하는 Replicat 설정
# 담당: OCI GG 담당자
# 예상 소요: 30분
#
# 중요: Replicat은 이 단계에서 등록하되, 실제 시작(START)은 STEP 16에서 수행
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step06_replicat_setup")
echo "=== STEP 06. Replicat (REP1) 파라미터 설정 및 등록 ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

###############################################################################
# 6-1. Replicat 등록
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 6-1. Replicat 등록 ---" | tee -a "$LOG"

echo "
ADD REPLICAT ${GG_REPLICAT_NAME}, INTEGRATED, EXTTRAIL oci://${OCI_BUCKET}@${OCI_NAMESPACE}/trail/rt
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

###############################################################################
# 6-2. Replicat 파라미터 파일 작성
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 6-2. Replicat 파라미터 파일 작성 ---" | tee -a "$LOG"

# Replicat 파라미터 내용
REPLICAT_PARAMS="REPLICAT ${GG_REPLICAT_NAME}
USERIDALIAS ggadmin_tgt DOMAIN OracleGoldenGate
SOURCETIMEZONE +09:00

-- 소스/타겟 구조 완전 동일한 경우 ASSUMETARGETDEFS 사용
-- Tablespace 리맵핑 등 구조 변경이 있으면 DEFS 파일 생성 후 SOURCEDEFS 사용
ASSUMETARGETDEFS

-- Trigger 이중 실행 방지 (필수 — GG Replicat 세션에서 Trigger 비활성화)
SUPPRESSTRIGGERS

-- 초기 적재(impdp) 데이터와의 충돌 자동 처리 (데이터 동기화 완료 후 반드시 제거)
HANDLECOLLISIONS

-- 전체 DB 이전: 와일드카드로 전체 사용자 스키마 매핑
-- (시스템 스키마는 Extract에서 이미 제외 → Trail에 포함되지 않음)
MAP *.*, TARGET *.*;
SEQUENCE *.*;"

echo "GGSCI에서 EDIT PARAMS ${GG_REPLICAT_NAME} 실행 후 아래 내용을 저장:" | tee -a "$LOG"
echo "${REPLICAT_PARAMS}" | tee -a "$LOG"

# GGSCI로 파라미터 파일 작성
echo "
EDIT PARAMS ${GG_REPLICAT_NAME}
${REPLICAT_PARAMS}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "HANDLECOLLISIONS 주의사항:" | tee -a "$LOG"
echo "  - 초기 데이터 적재(impdp) 이후 GG 복제 시작 시 중복 데이터 충돌 방지용" | tee -a "$LOG"
echo "  - GG 동기화가 완전히 안정화된 후 (LAG < 30초, 24h 유지) 반드시 제거" | tee -a "$LOG"
echo "  - 제거 방법: STOP REPLICAT REP1 → EDIT PARAMS REP1 (해당 줄 삭제) → START REPLICAT REP1" | tee -a "$LOG"

###############################################################################
# 6-3. Replicat 파라미터 검증
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 6-3. Replicat 파라미터 검증 ---" | tee -a "$LOG"

echo "
VIEW PARAMS ${GG_REPLICAT_NAME}
INFO REPLICAT ${GG_REPLICAT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo ">> INFO REPLICAT 상태: STOPPED (아직 START 하지 않음 — 정상)" | tee -a "$LOG"

###############################################################################
# 6-4. SUPPRESSTRIGGERS 적용 확인 (참고 사항)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 6-4. SUPPRESSTRIGGERS 적용 확인 ---" | tee -a "$LOG"
echo "GG Replicat 세션에서 Trigger가 실행되지 않는지 확인" | tee -a "$LOG"
echo "  (GG 시작 후 STATS REPLICAT REP1으로 간접 확인 가능)" | tee -a "$LOG"
echo "  Trigger가 있는 테이블에 대해 타겟 Trigger DISABLE도 병행 적용 (Phase 4에서 수행)" | tee -a "$LOG"

###############################################################################
# 6-5. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 6-5. 결과 요약 ---" | tee -a "$LOG"
echo "  - ADD REPLICAT ${GG_REPLICAT_NAME} 등록 확인" | tee -a "$LOG"
echo "  - ASSUMETARGETDEFS 설정 확인" | tee -a "$LOG"
echo "  - SUPPRESSTRIGGERS 설정 확인" | tee -a "$LOG"
echo "  - HANDLECOLLISIONS 설정 확인 (동기화 안정화 후 반드시 제거)" | tee -a "$LOG"
echo "  - MAP *.* TARGET *.* 설정 확인" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 06 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
