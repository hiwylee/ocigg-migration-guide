#!/usr/bin/env bash
###############################################################################
# step04_extract_setup.sh — Extract(EXT1) 파라미터 및 등록
# 실행 환경: [GG]
# 목적: 소스 RDS Redo Log에서 변경 데이터를 추출하는 Extract 프로세스 설정
# 담당: OCI GG 담당자
# 예상 소요: 30분
#
# 중요: Extract는 이 단계에서 등록하되, 실제 시작(START)은 STEP 09에서
#       expdp SCN 기록 후 수행
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step04_extract_setup")
echo "=== STEP 04. Extract (EXT1) 파라미터 설정 및 등록 ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

###############################################################################
# 4-1. Extract Trail 등록
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 4-1. Extract Trail 등록 ---" | tee -a "$LOG"

echo "
ADD EXTRACT ${GG_EXTRACT_NAME}, INTEGRATED TRANLOG, BEGIN NOW
ADD EXTTRAIL ./dirdat/aa, EXTRACT ${GG_EXTRACT_NAME}, MEGABYTES 500
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

###############################################################################
# 4-2. Extract 파라미터 파일 작성
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 4-2. Extract 파라미터 파일 작성 ---" | tee -a "$LOG"

# Extract 파라미터 내용 (전체 DB 이전 — 시스템 스키마 제외)
EXTRACT_PARAMS="EXTRACT ${GG_EXTRACT_NAME}
USERIDALIAS ggadmin_src DOMAIN OracleGoldenGate
EXTTRAIL ./dirdat/aa
SOURCETIMEZONE +09:00

-- SE 제약: 지원 범위 내 DDL 복제만 설정
DDL INCLUDE MAPPED OBJTYPE 'TABLE' OPTYPE CREATE, ALTER, DROP, TRUNCATE

-- 시스템 스키마 명시적 제외 (와일드카드 TABLE *.* 와 함께 사용)
TABLEEXCLUDE SYS.*;
TABLEEXCLUDE SYSTEM.*;
TABLEEXCLUDE OUTLN.*;
TABLEEXCLUDE DBSNMP.*;
TABLEEXCLUDE APPQOSSYS.*;
TABLEEXCLUDE AUDSYS.*;
TABLEEXCLUDE CTXSYS.*;
TABLEEXCLUDE DBSFWUSER.*;
TABLEEXCLUDE DVSYS.*;
TABLEEXCLUDE EXFSYS.*;
TABLEEXCLUDE GGSYS.*;
TABLEEXCLUDE GSMADMIN_INTERNAL.*;
TABLEEXCLUDE LBACSYS.*;
TABLEEXCLUDE MDSYS.*;
TABLEEXCLUDE OJVMSYS.*;
TABLEEXCLUDE OLAPSYS.*;
TABLEEXCLUDE ORDDATA.*;
TABLEEXCLUDE ORDSYS.*;
TABLEEXCLUDE WMSYS.*;
TABLEEXCLUDE XDB.*;
-- GoldenGate 자체 스키마 반드시 제외
TABLEEXCLUDE GGADMIN.*;
TABLEEXCLUDE GGS_TEMP.*;

-- 전체 사용자 스키마 복제 (와일드카드)
TABLE *.*;
SEQUENCE *.*;"

echo "GGSCI에서 EDIT PARAMS ${GG_EXTRACT_NAME} 실행 후 아래 내용을 저장:" | tee -a "$LOG"
echo "${EXTRACT_PARAMS}" | tee -a "$LOG"

# GGSCI로 파라미터 파일 직접 작성 (heredoc pipe)
echo "
EDIT PARAMS ${GG_EXTRACT_NAME}
${EXTRACT_PARAMS}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "주의사항:" | tee -a "$LOG"
echo "  - XMLTYPE Object-Relational 방식 테이블 존재 시 해당 테이블 TABLEEXCLUDE 추가 필요" | tee -a "$LOG"
echo "  - SE 환경에서 GG DDL 복제는 지원 범위가 제한됨" | tee -a "$LOG"
echo "  - 미지원 DDL 발생 시 수동 처리 절차 별도 수립" | tee -a "$LOG"

###############################################################################
# 4-3. Extract 파라미터 검증
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 4-3. Extract 파라미터 검증 ---" | tee -a "$LOG"

echo "
VIEW PARAMS ${GG_EXTRACT_NAME}
INFO EXTRACT ${GG_EXTRACT_NAME}
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo ">> INFO EXTRACT 상태: STOPPED (아직 START 하지 않음 — 정상)" | tee -a "$LOG"

###############################################################################
# 4-4. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 4-4. 결과 요약 ---" | tee -a "$LOG"
echo "  - ADD EXTRACT ${GG_EXTRACT_NAME} 등록 확인" | tee -a "$LOG"
echo "  - ADD EXTTRAIL 등록 확인" | tee -a "$LOG"
echo "  - 파라미터 파일 저장 확인" | tee -a "$LOG"
echo "  - TABLEEXCLUDE 시스템 스키마 전체 포함 확인" | tee -a "$LOG"
echo "  - TABLE *.* / SEQUENCE *.* 설정 확인" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 04 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
