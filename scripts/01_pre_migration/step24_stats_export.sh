#!/usr/bin/env bash
set -euo pipefail
###############################################################################
# step24_stats_export.sh — 통계정보 Export (STEP 24)
# 실행 환경: [소스]
# 목적: 소스의 정확한 옵티마이저 통계를 타겟으로 이전하여 실행 계획 안정성 확보
# 담당: 소스 DBA
# 선택: 옵션 A(소스 통계 이전 -- 권장) 또는 옵션 B(타겟 Fresh 수집)
###############################################################################
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step24_stats_export")
echo "=== STEP 24. 소스 통계정보 Export (옵션 A) ===" | tee "${LOG}"
echo "실행 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

# ─────────────────────────────────────────────
# 24-1. 통계 스테이징 테이블 생성 및 Export
# ─────────────────────────────────────────────
echo "--- [24-1] 통계 스테이징 테이블 생성 및 통계 Export ---" | tee -a "${LOG}"

${SRC_SQLPLUS_CONN} ${SRC_MIG_USER}/${SRC_MIG_PASS}@"${SRC_TNS}" <<'EOSQL' | tee -a "${LOG}"
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK ON

-- 통계 스테이징 테이블 생성
BEGIN
    DBMS_STATS.CREATE_STAT_TABLE(
        ownname  => 'MIGRATION_USER',
        stattab  => 'STATS_EXPORT_TABLE',
        tblspace => 'USERS'
    );
    DBMS_OUTPUT.PUT_LINE('STATS_EXPORT_TABLE 생성 완료');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -20002 THEN
            DBMS_OUTPUT.PUT_LINE('STATS_EXPORT_TABLE 이미 존재 - 기존 테이블 사용');
        ELSE
            RAISE;
        END IF;
END;
/

-- 전체 DB 통계 Export (전체 사용자 스키마 + 딕셔너리 통계)
BEGIN
    DBMS_STATS.EXPORT_DATABASE_STATS(
        stattab => 'STATS_EXPORT_TABLE',
        statown => 'MIGRATION_USER'
    );
    DBMS_OUTPUT.PUT_LINE('DB 통계 Export 완료');
END;
/

-- Export 완료 확인
SELECT COUNT(*) AS STAT_ROW_CNT FROM MIGRATION_USER.STATS_EXPORT_TABLE;
-- 수천 건 이상이면 정상

EXIT;
EOSQL

SQL_EXIT=$?
if [ ${SQL_EXIT} -ne 0 ]; then
    echo "[실패] 통계 Export SQL 실행 실패 (종료 코드: ${SQL_EXIT})" | tee -a "${LOG}"
    exit 1
fi

# ─────────────────────────────────────────────
# 24-2. 통계 테이블을 덤프 파일로 Export
# ─────────────────────────────────────────────
echo "" | tee -a "${LOG}"
echo "--- 통계 테이블 expdp ---" | tee -a "${LOG}"

expdp ${SRC_MIG_USER}/${SRC_MIG_PASS}@"${SRC_TNS}" \
    TABLES=MIGRATION_USER.STATS_EXPORT_TABLE \
    DUMPFILE=stats_export.dmp \
    LOGFILE=stats_export.log \
    DIRECTORY=${EXPDP_DIR} \
    2>&1 | tee -a "${LOG}"

EXPDP_EXIT=$?
if [ ${EXPDP_EXIT} -ne 0 ]; then
    echo "[실패] expdp 종료 코드: ${EXPDP_EXIT}" | tee -a "${LOG}"
    exit 1
fi

# ─────────────────────────────────────────────
# 24-3. OCI Object Storage로 전송
# ─────────────────────────────────────────────
echo "" | tee -a "${LOG}"
echo "--- OCI Object Storage 전송 ---" | tee -a "${LOG}"

oci os object bulk-upload \
    --bucket-name migration-dump-bucket \
    --src-dir ${EXPDP_DUMP_PATH}/ \
    --include "stats_export.dmp" \
    --prefix stats/ \
    2>&1 | tee -a "${LOG}"

UPLOAD_EXIT=$?
if [ ${UPLOAD_EXIT} -ne 0 ]; then
    echo "[실패] OCI Object Storage 업로드 실패 (종료 코드: ${UPLOAD_EXIT})" | tee -a "${LOG}"
    exit 1
fi

echo "" | tee -a "${LOG}"
echo "[완료] STEP 24 통계정보 Export 완료" | tee -a "${LOG}"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "로그 파일: ${LOG}"
