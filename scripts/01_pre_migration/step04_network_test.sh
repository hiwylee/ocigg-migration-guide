#!/usr/bin/env bash
set -euo pipefail
###############################################################################
# step04_network_test.sh — 네트워크 연결 테스트 (STEP 04)
# 실행 환경: [로컬]
# 목적: AWS RDS <-> OCI GG <-> OCI DBCS 구간 네트워크 연통 확인
# 담당: 인프라/네트워크 담당
###############################################################################
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step04_network_test")
echo "=== STEP 04. 네트워크 연결 테스트 ===" | tee "${LOG}"
echo "실행 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

PASS_COUNT=0
FAIL_COUNT=0

# ─────────────────────────────────────────────
# 함수: TCP 연결 테스트 (tnsping 또는 nc 사용)
# ─────────────────────────────────────────────
test_tcp_connection() {
    local label="$1"
    local host="$2"
    local port="$3"

    echo "--- [테스트] ${label} (${host}:${port}) ---" | tee -a "${LOG}"

    # nc(netcat) 으로 TCP 연결 테스트 (타임아웃 5초)
    if nc -z -w 5 "${host}" "${port}" 2>/dev/null; then
        echo "  결과: 성공 (TCP 연결 가능)" | tee -a "${LOG}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  결과: 실패 (TCP 연결 불가 - 방화벽/보안그룹 확인 필요)" | tee -a "${LOG}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo "" | tee -a "${LOG}"
}

# ─────────────────────────────────────────────
# 함수: sqlplus 연결 테스트
# ─────────────────────────────────────────────
test_sqlplus_connection() {
    local label="$1"
    local user="$2"
    local pass="$3"
    local tns="$4"

    echo "--- [테스트] ${label} (sqlplus ${user}) ---" | tee -a "${LOG}"

    result=$(sqlplus -S "${user}/${pass}@${tns}" <<'EOSQL'
SET HEADING OFF
SET FEEDBACK OFF
SELECT 'CONNECTION_OK: ' || SYSDATE FROM DUAL;
EXIT;
EOSQL
)
    if echo "${result}" | grep -q "CONNECTION_OK"; then
        echo "  결과: 성공 - ${result}" | tee -a "${LOG}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  결과: 실패" | tee -a "${LOG}"
        echo "  에러: ${result}" | tee -a "${LOG}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo "" | tee -a "${LOG}"
}

# ─────────────────────────────────────────────
# 1. TCP 연결 테스트
# ─────────────────────────────────────────────
echo "=============================================" | tee -a "${LOG}"
echo "[4-3] TCP 연결 테스트" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

test_tcp_connection "배스천 -> 소스 RDS (1521)" "${SRC_DB_HOST}" "${SRC_DB_PORT}"
test_tcp_connection "배스천 -> 타겟 DBCS (1521)" "${TGT_DB_HOST}" "${TGT_DB_PORT}"

# ─────────────────────────────────────────────
# 2. sqlplus 연결 테스트
# ─────────────────────────────────────────────
echo "=============================================" | tee -a "${LOG}"
echo "[4-3] sqlplus 연결 테스트" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

# OCI GG -> 소스 RDS 연결 테스트
test_sqlplus_connection "소스 RDS GGADMIN 접속" \
    "${SRC_GG_USER}" "${SRC_GG_PASS}" "${SRC_TNS}"

# 타겟 DBCS 연결 테스트
test_sqlplus_connection "타겟 DBCS GGADMIN 접속" \
    "${TGT_GG_USER}" "${TGT_GG_PASS}" "${TGT_TNS}"

# ─────────────────────────────────────────────
# 결과 요약
# ─────────────────────────────────────────────
echo "=============================================" | tee -a "${LOG}"
echo "네트워크 연결 테스트 결과 요약" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "  성공: ${PASS_COUNT} 건" | tee -a "${LOG}"
echo "  실패: ${FAIL_COUNT} 건" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

if [ "${FAIL_COUNT}" -gt 0 ]; then
    echo "[경고] 실패 항목 존재 - 네트워크/방화벽 담당자와 즉시 협의 후 재테스트 필요" | tee -a "${LOG}"
    exit 1
else
    echo "[완료] 모든 네트워크 연결 테스트 통과" | tee -a "${LOG}"
fi

echo "" | tee -a "${LOG}"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "로그 파일: ${LOG}"
