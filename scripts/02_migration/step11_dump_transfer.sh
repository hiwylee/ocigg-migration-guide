#!/usr/bin/env bash
###############################################################################
# step11_dump_transfer.sh — Dump 파일 OCI Object Storage 전송
# 실행 환경: [소스] / [타겟] / [로컬]
# 목적: 소스 RDS의 Dump 파일을 OCI Object Storage를 경유하여 타겟 DBCS로 전송
# 담당: 소스 DBA, 인프라 담당
# 예상 소요: 네트워크 대역폭에 따라 수 시간
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step11_dump_transfer")
echo "=== STEP 11. Dump 파일 OCI Object Storage 전송 ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

# 환경변수에서 버킷명 참조 (env.sh의 OCI_BUCKET)
DUMP_BUCKET="${OCI_BUCKET}"

###############################################################################
# 11-1. OCI CLI 설정 확인 (소스 측)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 11-1. OCI CLI 설정 확인 ---" | tee -a "$LOG"

oci --version 2>&1 | tee -a "$LOG"

# Namespace 확인
echo "OCI Namespace 확인:" | tee -a "$LOG"
oci os ns get 2>&1 | tee -a "$LOG"
# 기대값: {"data": "<namespace>"}

###############################################################################
# 11-2. Dump 파일 OCI Object Storage 업로드
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 11-2. Dump 파일 OCI Object Storage 업로드 ---" | tee -a "$LOG"

# 데이터 Dump 파일 업로드
echo "데이터 Dump 파일 업로드 시작..." | tee -a "$LOG"
oci os object bulk-upload \
    --bucket-name "${DUMP_BUCKET}" \
    --src-dir "${EXPDP_DUMP_PATH}/" \
    --include "fulldata_*.dmp" \
    --prefix fulldata/ \
    --multipart-threshold 100MB \
    --parallel-upload-count 3 \
    2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"

# 통계 Export 파일도 함께 업로드 (01.pre_migration.md STEP 24에서 생성)
echo "통계 Export 파일 업로드 시작..." | tee -a "$LOG"
oci os object bulk-upload \
    --bucket-name "${DUMP_BUCKET}" \
    --src-dir "${EXPDP_DUMP_PATH}/" \
    --include "stats_export.dmp" \
    --prefix stats/ \
    2>&1 | tee -a "$LOG"

###############################################################################
# 11-3. 업로드 완료 및 파일 무결성 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 11-3. 업로드 완료 및 파일 무결성 확인 ---" | tee -a "$LOG"

# OCI Object Storage 오브젝트 목록 확인
echo "업로드된 오브젝트 목록:" | tee -a "$LOG"
oci os object list \
    --bucket-name "${DUMP_BUCKET}" \
    --prefix fulldata/ \
    --query 'data[].{name:name, size:size}' \
    --output table \
    2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"

# MD5 체크섬 비교 (선택 사항 — 대용량 파일 무결성 확인)
echo "첫 번째 Dump 파일 메타데이터 확인:" | tee -a "$LOG"
oci os object head \
    --bucket-name "${DUMP_BUCKET}" \
    --name fulldata/fulldata_01.dmp \
    2>&1 | tee -a "$LOG"

###############################################################################
# 11-4. 타겟 DBCS로 Dump 파일 다운로드
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 11-4. 타겟 DBCS로 Dump 파일 다운로드 ---" | tee -a "$LOG"

# 다운로드 디렉토리 생성
mkdir -p /u01/backup/dump/

# 데이터 Dump 파일 다운로드
echo "데이터 Dump 파일 다운로드 시작..." | tee -a "$LOG"
oci os object bulk-download \
    --bucket-name "${DUMP_BUCKET}" \
    --download-dir /u01/backup/dump/ \
    --prefix fulldata/ \
    --parallel-download-count 3 \
    2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"

# 통계 Export 파일 다운로드
echo "통계 Export 파일 다운로드 시작..." | tee -a "$LOG"
oci os object bulk-download \
    --bucket-name "${DUMP_BUCKET}" \
    --download-dir /u01/backup/dump/ \
    --prefix stats/ \
    2>&1 | tee -a "$LOG"

###############################################################################
# 11-5. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 11-5. 결과 요약 ---" | tee -a "$LOG"
echo "  - OCI Object Storage 업로드 완료 확인" | tee -a "$LOG"
echo "  - 파일 개수 소스/타겟 일치 확인" | tee -a "$LOG"
echo "  - 타겟 DBCS 다운로드 완료 확인" | tee -a "$LOG"
echo "  - 디스크 여유 공간 충분 (Dump 크기 x 2 이상) 확인" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 11 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
