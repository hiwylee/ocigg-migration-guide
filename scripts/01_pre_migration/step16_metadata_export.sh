#!/usr/bin/env bash
set -euo pipefail
###############################################################################
# step16_metadata_export.sh — METADATA_ONLY expdp (STEP 16)
# 실행 환경: [소스]
# 목적: 소스 전체 DB의 DDL 구조(스키마, 테이블, 인덱스, 제약 등)를 덤프 파일로 추출
# 담당: 소스 DBA
# 주의: 이 단계에서 데이터는 포함하지 않음 -- 구조만 추출
###############################################################################
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step16_metadata_export")
echo "=== STEP 16. METADATA_ONLY expdp ===" | tee "${LOG}"
echo "실행 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

# ─────────────────────────────────────────────
# 1. Tablespace 이름 매핑이 필요한 경우 사전 확인
# ─────────────────────────────────────────────
echo "--- Tablespace 목록 사전 확인 ---" | tee -a "${LOG}"
${SRC_SQLPLUS_CONN} ${SRC_MIG_USER}/${SRC_MIG_PASS}@"${SRC_TNS}" <<'EOSQL' | tee -a "${LOG}"
SET HEADING ON
SET LINESIZE 200
SET PAGESIZE 100
SELECT DISTINCT TABLESPACE_NAME FROM DBA_SEGMENTS
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY TABLESPACE_NAME;
EXIT;
EOSQL

# ─────────────────────────────────────────────
# 2. METADATA_ONLY expdp 실행
# ─────────────────────────────────────────────
echo "" | tee -a "${LOG}"
echo "--- METADATA_ONLY Export 시작 ---" | tee -a "${LOG}"
echo "Export 시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"

expdp ${SRC_MIG_USER}/${SRC_MIG_PASS}@"${SRC_TNS}" \
    FULL=Y \
    CONTENT=METADATA_ONLY \
    DUMPFILE=metadata_%U.dmp \
    LOGFILE=metadata_export.log \
    EXCLUDE=STATISTICS \
    DIRECTORY=${EXPDP_DIR} \
    LOGTIME=ALL \
    2>&1 | tee -a "${LOG}"

EXPDP_EXIT=$?

echo "" | tee -a "${LOG}"
echo "Export 완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"

# ─────────────────────────────────────────────
# 3. Export 완료 확인
# ─────────────────────────────────────────────
echo "" | tee -a "${LOG}"
echo "--- Export 로그 마지막 줄 확인 ---" | tee -a "${LOG}"
tail -20 ${EXPDP_DUMP_PATH}/metadata_export.log 2>/dev/null | tee -a "${LOG}"

if [ ${EXPDP_EXIT} -ne 0 ]; then
    echo "[실패] expdp 종료 코드: ${EXPDP_EXIT}" | tee -a "${LOG}"
    exit 1
fi

# ─────────────────────────────────────────────
# 4. 덤프 파일 OCI Object Storage 전송
# ─────────────────────────────────────────────
echo "" | tee -a "${LOG}"
echo "--- OCI Object Storage 업로드 ---" | tee -a "${LOG}"

oci os object bulk-upload \
    --bucket-name migration-dump-bucket \
    --src-dir ${EXPDP_DUMP_PATH}/ \
    --prefix metadata/ \
    --include "metadata_*.dmp" \
    --multipart-threshold 100MB \
    2>&1 | tee -a "${LOG}"

UPLOAD_EXIT=$?

if [ ${UPLOAD_EXIT} -ne 0 ]; then
    echo "[실패] OCI Object Storage 업로드 실패 (종료 코드: ${UPLOAD_EXIT})" | tee -a "${LOG}"
    exit 1
fi

echo "" | tee -a "${LOG}"
echo "[완료] STEP 16 METADATA_ONLY expdp 및 전송 완료" | tee -a "${LOG}"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "로그 파일: ${LOG}"
