#!/usr/bin/env bash
###############################################################################
# env.sh — 공통 환경변수 설정
# 실행 환경: [로컬] — 모든 스크립트에서 source ../config/env.sh 로 참조
###############################################################################
set -euo pipefail

# ─────────────────────────────────────────────
# 프로젝트 기본 경로
# ─────────────────────────────────────────────
export SCRIPT_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LOG_DIR="${SCRIPT_BASE_DIR}/logs"
mkdir -p "${LOG_DIR}"

# ─────────────────────────────────────────────
# 소스 DB (AWS RDS Oracle SE)
# ─────────────────────────────────────────────
export SRC_DB_HOST="<SOURCE_RDS_ENDPOINT>"
export SRC_DB_PORT="1521"
export SRC_DB_SID="<SOURCE_SID>"
export SRC_DB_SERVICE="<SOURCE_SERVICE_NAME>"
export SRC_SQLPLUS_CONN="sqlplus -S"

# 소스 DBA 계정
export SRC_DBA_USER="admin"
export SRC_DBA_PASS="<SOURCE_DBA_PASSWORD>"

# 소스 GG 계정
export SRC_GG_USER="GGADMIN"
export SRC_GG_PASS="<SOURCE_GG_PASSWORD>"

# 소스 마이그레이션 계정
export SRC_MIG_USER="MIGRATION_USER"
export SRC_MIG_PASS="<SOURCE_MIG_PASSWORD>"

# 소스 TNS 접속 문자열
export SRC_TNS="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SRC_DB_HOST})(PORT=${SRC_DB_PORT}))(CONNECT_DATA=(SID=${SRC_DB_SID})))"

# ─────────────────────────────────────────────
# 타겟 DB (OCI DBCS Oracle SE)
# ─────────────────────────────────────────────
export TGT_DB_HOST="<TARGET_DBCS_HOST>"
export TGT_DB_PORT="1521"
export TGT_DB_SID="<TARGET_SID>"
export TGT_DB_SERVICE="<TARGET_SERVICE_NAME>"
export TGT_SQLPLUS_CONN="sqlplus -S"

# 타겟 DBA 계정
export TGT_DBA_USER="SYS"
export TGT_DBA_PASS="<TARGET_DBA_PASSWORD>"

# 타겟 GG 계정
export TGT_GG_USER="GGADMIN"
export TGT_GG_PASS="<TARGET_GG_PASSWORD>"

# 타겟 마이그레이션 계정
export TGT_MIG_USER="MIGRATION_USER"
export TGT_MIG_PASS="<TARGET_MIG_PASSWORD>"

# 타겟 TNS 접속 문자열
export TGT_TNS="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${TGT_DB_HOST})(PORT=${TGT_DB_PORT}))(CONNECT_DATA=(SID=${TGT_DB_SID})))"

# ─────────────────────────────────────────────
# OCI GoldenGate
# ─────────────────────────────────────────────
export GG_ADMIN_URL="<GG_ADMIN_SERVER_URL>"
export GG_ADMIN_USER="oggadmin"
export GG_ADMIN_PASS="<GG_ADMIN_PASSWORD>"
export GG_DEPLOYMENT_NAME="<GG_DEPLOYMENT_NAME>"

# GG 프로세스 이름
export GG_EXTRACT_NAME="EXT1"
export GG_PUMP_NAME="PUMP1"
export GG_REPLICAT_NAME="REP1"

# GGSCI 경로
export GGSCI_HOME="<GG_HOME>/bin"
export GGSCI="${GGSCI_HOME}/ggsci"

# ─────────────────────────────────────────────
# OCI Object Storage
# ─────────────────────────────────────────────
export OCI_NAMESPACE="<OCI_NAMESPACE>"
export OCI_BUCKET="<OCI_BUCKET_NAME>"
export OCI_REGION="<OCI_REGION>"

# ─────────────────────────────────────────────
# Data Pump 경로 (expdp / impdp)
# ─────────────────────────────────────────────
export EXPDP_DIR="DATA_PUMP_DIR"
export EXPDP_DUMP_PATH="/rdsdbdata/datapump"
export IMPDP_DIR="DATA_PUMP_DIR"
export IMPDP_DUMP_PATH="/u01/app/oracle/admin/datapump"

# ─────────────────────────────────────────────
# 마이그레이션 대상 스키마 (쉼표 구분)
# ─────────────────────────────────────────────
export MIGRATION_SCHEMAS="<SCHEMA1>,<SCHEMA2>"
export MIGRATION_SCHEMAS_QUOTED="'<SCHEMA1>','<SCHEMA2>'"

# 시스템 스키마 제외 목록 (SQL WHERE 절용)
export SYS_EXCLUDE_LIST="'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS','DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS\$NULL','GGADMIN','GGS_TEMP','MIGRATION_USER'"

# ─────────────────────────────────────────────
# 타임스탬프 함수
# ─────────────────────────────────────────────
timestamp() {
    date '+%Y%m%d_%H%M%S'
}

log_file() {
    local prefix="$1"
    echo "${LOG_DIR}/${prefix}_$(timestamp).log"
}

echo "[env.sh] 환경변수 로드 완료 — $(date '+%Y-%m-%d %H:%M:%S')"
