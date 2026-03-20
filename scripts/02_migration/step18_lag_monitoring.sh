#!/usr/bin/env bash
###############################################################################
# step18_lag_monitoring.sh — LAG 안정화 모니터링 (24h+)
# 실행 환경: [GG]
# 목적: Extract/Replicat LAG이 30초 이하로 24시간 이상 지속적으로 유지되는지 모니터링
# 담당: OCI GG 담당자, 타겟 DBA
# 예상 소요: 24시간 이상 (연속 모니터링)
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step18_lag_monitoring")
echo "=== STEP 18. LAG 안정화 모니터링 (24h+) ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

# 모니터링 간격 (초) — 기본 300초 (5분)
MONITOR_INTERVAL=${MONITOR_INTERVAL:-300}
# 모니터링 최대 반복 횟수 — 기본 288회 (5분 x 288 = 24시간)
MAX_ITERATIONS=${MAX_ITERATIONS:-288}
# LAG 임계치 (초)
LAG_THRESHOLD=30

echo "모니터링 간격: ${MONITOR_INTERVAL}초" | tee -a "$LOG"
echo "최대 반복 횟수: ${MAX_ITERATIONS}회" | tee -a "$LOG"
echo "LAG 임계치: ${LAG_THRESHOLD}초" | tee -a "$LOG"

###############################################################################
# 18-1. LAG 모니터링 (주기적 실행)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 18-1. LAG 모니터링 시작 ---" | tee -a "$LOG"
echo "확인 시각 | EXT1 LAG | PUMP1 LAG | REP1 LAG | 비고" | tee -a "$LOG"
echo "---------|---------|----------|---------|----" | tee -a "$LOG"

for ((i=1; i<=MAX_ITERATIONS; i++)); do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Extract LAG 확인
    EXT_LAG=$(echo "
LAG EXTRACT ${GG_EXTRACT_NAME}
EXIT
" | ${GGSCI} 2>&1 | grep -i "lag" || echo "N/A")

    # Pump LAG 확인
    PUMP_LAG=$(echo "
LAG EXTRACT ${GG_PUMP_NAME}
EXIT
" | ${GGSCI} 2>&1 | grep -i "lag" || echo "N/A")

    # Replicat LAG 확인
    REP_LAG=$(echo "
LAG REPLICAT ${GG_REPLICAT_NAME}
EXIT
" | ${GGSCI} 2>&1 | grep -i "lag" || echo "N/A")

    # SEND GETLAG 방식도 실행
    echo "
SEND EXTRACT ${GG_EXTRACT_NAME}, GETLAG
SEND REPLICAT ${GG_REPLICAT_NAME}, GETLAG
EXIT
" | ${GGSCI} 2>&1 >> "$LOG"

    # 결과 기록
    echo "${TIMESTAMP} | ${EXT_LAG} | ${PUMP_LAG} | ${REP_LAG} |" | tee -a "$LOG"

    # Discard 파일 점검 (매 반복마다)
    DISCARD_CHECK=$(echo "
VIEW DISCARD ${GG_REPLICAT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tail -5)
    echo "  Discard: ${DISCARD_CHECK}" >> "$LOG"

    # 프로세스 상태 점검
    STATUS_CHECK=$(echo "
INFO ALL
EXIT
" | ${GGSCI} 2>&1)
    echo "  Status: ${STATUS_CHECK}" >> "$LOG"

    # ABEND 감지 시 경고
    if echo "${STATUS_CHECK}" | grep -qi "ABEND"; then
        echo "*** ABEND 감지! 즉시 확인 필요 ***" | tee -a "$LOG"
    fi

    # 마지막 반복이 아니면 대기
    if [ $i -lt $MAX_ITERATIONS ]; then
        sleep ${MONITOR_INTERVAL}
    fi
done

###############################################################################
# 18-2. OCI GG 콘솔 모니터링 설정 (안내)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 18-2. OCI GG 콘솔 모니터링 설정 (수동 작업) ---" | tee -a "$LOG"
cat <<'CONSOLE_MSG' | tee -a "$LOG"
[OCI콘솔] GoldenGate → Deployments → Metrics
  - Extract LAG: 임계치 30초 알람 설정
  - Replicat LAG: 임계치 30초 알람 설정
  - 프로세스 ABEND: 즉시 알람 설정

[OCI콘솔] Monitoring → Alarms → Create Alarm
  - 메트릭 네임스페이스: oci_goldengate
  - 임계치: LAG > 30s → Notification 발송
CONSOLE_MSG

###############################################################################
# 18-3. LAG 안정화 기준 체크리스트 (안내)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 18-3. LAG 안정화 기준 체크리스트 ---" | tee -a "$LOG"
echo "아래 모든 조건이 24시간 연속 유지되어야 Phase 6(검증)로 전환 가능:" | tee -a "$LOG"
echo "  - Extract LAG < ${LAG_THRESHOLD}초 (24h+)" | tee -a "$LOG"
echo "  - Pump LAG < ${LAG_THRESHOLD}초 (24h+)" | tee -a "$LOG"
echo "  - Replicat LAG < ${LAG_THRESHOLD}초 (24h+)" | tee -a "$LOG"
echo "  - Discard 파일 레코드 0건 (누적)" | tee -a "$LOG"
echo "  - ABEND 이력 없음" | tee -a "$LOG"

###############################################################################
# 18-4. HANDLECOLLISIONS 제거 (LAG 안정화 후 수동 실행)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 18-4. HANDLECOLLISIONS 제거 (LAG 안정화 후 수동 실행) ---" | tee -a "$LOG"
echo "전제 조건: Extract/Replicat LAG < 30초가 24시간 이상 유지된 후 수행" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "GGSCI에서 수동 실행:" | tee -a "$LOG"
echo "  STOP REPLICAT ${GG_REPLICAT_NAME}" | tee -a "$LOG"
echo "  EDIT PARAMS ${GG_REPLICAT_NAME}" | tee -a "$LOG"
echo "  -- HANDLECOLLISIONS 라인 제거 및 저장" | tee -a "$LOG"
echo "  START REPLICAT ${GG_REPLICAT_NAME}" | tee -a "$LOG"
echo "  STATUS REPLICAT ${GG_REPLICAT_NAME}" | tee -a "$LOG"
echo "  -- 기대값: RUNNING" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "이유: HANDLECOLLISIONS는 초기 적재 충돌 처리용" | tee -a "$LOG"
echo "      완전 동기화 이후 존재 시 실제 데이터 충돌을 무시하는 문제 발생 가능" | tee -a "$LOG"

###############################################################################
# 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 결과 요약 ---" | tee -a "$LOG"
echo "모니터링 종료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 18 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
