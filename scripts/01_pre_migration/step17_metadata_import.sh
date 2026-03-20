#!/usr/bin/env bash
set -euo pipefail
###############################################################################
# step17_metadata_import.sh — METADATA_ONLY impdp (STEP 17)
# 실행 환경: [타겟]
# 목적: 소스에서 추출한 DDL 구조를 타겟 DBCS에 Import
# 담당: 타겟 DBA
###############################################################################
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step17_metadata_import")
echo "=== STEP 17. METADATA_ONLY impdp ===" | tee "${LOG}"
echo "실행 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

# ─────────────────────────────────────────────
# 17-1. Tablespace 사전 생성 (소스와 다를 경우)
# ─────────────────────────────────────────────
echo "--- [17-1] Tablespace 사전 확인 ---" | tee -a "${LOG}"
${TGT_SQLPLUS_CONN} ${TGT_DBA_USER}/${TGT_DBA_PASS}@"${TGT_TNS}" AS SYSDBA <<'EOSQL' | tee -a "${LOG}"
SET HEADING ON
SET LINESIZE 200
SET PAGESIZE 100

-- 소스 Tablespace 목록 확인 (STEP 16 준비 시 수집한 목록 기반)
SELECT DISTINCT TABLESPACE_NAME FROM DBA_TABLESPACES
WHERE CONTENTS = 'PERMANENT'
AND TABLESPACE_NAME NOT IN ('SYSTEM','SYSAUX','UNDOTBS1','TEMP');

-- 타겟에 없는 Tablespace 생성 (필요한 경우 아래 주석 해제)
-- CREATE TABLESPACE <TS_NAME>
--     DATAFILE SIZE 10G AUTOEXTEND ON NEXT 1G MAXSIZE UNLIMITED
--     EXTENT MANAGEMENT LOCAL AUTOALLOCATE
--     SEGMENT SPACE MANAGEMENT AUTO;

EXIT;
EOSQL

# ─────────────────────────────────────────────
# 17-2. OCI Object Storage에서 덤프 파일 다운로드
# ─────────────────────────────────────────────
echo "" | tee -a "${LOG}"
echo "--- OCI Object Storage 다운로드 ---" | tee -a "${LOG}"

oci os object bulk-download \
    --bucket-name migration-dump-bucket \
    --download-dir ${IMPDP_DUMP_PATH}/ \
    --prefix metadata/ \
    2>&1 | tee -a "${LOG}"

DOWNLOAD_EXIT=$?

if [ ${DOWNLOAD_EXIT} -ne 0 ]; then
    echo "[실패] OCI Object Storage 다운로드 실패 (종료 코드: ${DOWNLOAD_EXIT})" | tee -a "${LOG}"
    exit 1
fi

# ─────────────────────────────────────────────
# 17-2. METADATA_ONLY Import
# ─────────────────────────────────────────────
echo "" | tee -a "${LOG}"
echo "--- METADATA_ONLY Import 시작 ---" | tee -a "${LOG}"
echo "Import 시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"

# REMAP_TABLESPACE: 소스 Tablespace명 -> 타겟 Tablespace명 (이름이 다를 경우)
impdp ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" \
    FULL=Y \
    CONTENT=METADATA_ONLY \
    DUMPFILE=metadata_%U.dmp \
    LOGFILE=metadata_import.log \
    TABLE_EXISTS_ACTION=SKIP \
    EXCLUDE=STATISTICS \
    DIRECTORY=${IMPDP_DIR} \
    LOGTIME=ALL \
    2>&1 | tee -a "${LOG}"

IMPDP_EXIT=$?

echo "" | tee -a "${LOG}"
echo "Import 완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"

# ─────────────────────────────────────────────
# Import 완료 확인
# ─────────────────────────────────────────────
echo "" | tee -a "${LOG}"
echo "--- Import 로그 마지막 줄 확인 ---" | tee -a "${LOG}"
# 기대값: "Import: Release ... completed"
# ORA-39083, ORA-01435 등 무시 가능한 오류 목록 사전 파악
tail -30 ${IMPDP_DUMP_PATH}/metadata_import.log 2>/dev/null | tee -a "${LOG}"

if [ ${IMPDP_EXIT} -ne 0 ]; then
    echo "[경고] impdp 종료 코드: ${IMPDP_EXIT} (경고 포함 가능 - 로그 확인 필요)" | tee -a "${LOG}"
fi

echo "" | tee -a "${LOG}"
echo "[완료] STEP 17 METADATA_ONLY impdp 완료" | tee -a "${LOG}"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "로그 파일: ${LOG}"
