#!/usr/bin/env bash
###############################################################################
# step02_connection_setup.sh — 소스/타겟 Connection 생성 및 테스트
# 실행 환경: [GG] / [로컬]
# 목적: OCI GG가 소스 RDS 및 타겟 DBCS에 정상 접속되는지 검증
# 담당: OCI GG 담당자
# 예상 소요: 30분
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step02_connection_setup")
echo "=== STEP 02. 소스/타겟 Connection 생성 및 연결 테스트 ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

###############################################################################
# 2-1. Credential Store 설정 (GGSCI)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 2-1. Credential Store 설정 ---" | tee -a "$LOG"

echo "GGSCI에서 Credential Store 설정..." | tee -a "$LOG"
echo "
ADD CREDENTIALSTORE
ALTER CREDENTIALSTORE ADD USER ${SRC_GG_USER}@${SRC_DB_HOST}:${SRC_DB_PORT}/${SRC_DB_SERVICE} ALIAS ggadmin_src
ALTER CREDENTIALSTORE ADD USER ${TGT_GG_USER}@${TGT_DB_HOST}:${TGT_DB_PORT}/${TGT_DB_SERVICE} ALIAS ggadmin_tgt
INFO CREDENTIALSTORE
EXIT
" | ${GGSCI} 2>&1 | tee -a "$LOG"

echo ">> 두 개의 Alias(ggadmin_src, ggadmin_tgt) 등록 확인" | tee -a "$LOG"

###############################################################################
# 2-2. 소스 Connection 생성 (OCI콘솔 — 수동 확인)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 2-2. 소스 Connection 생성 (OCI콘솔 수동 작업) ---" | tee -a "$LOG"
cat <<'CONSOLE_MSG' | tee -a "$LOG"
[OCI콘솔] GoldenGate → Connections → Create Connection

[Source Connection]
  이름: SRC_RDS_CONN
  유형: Oracle Database
  Host: ${SRC_DB_HOST}
  Port: 1521
  Service Name: ${SRC_DB_SERVICE}
  Username: GGADMIN
  Password: <password>
  Wallet 파일: 해당 없음 (non-SSL)
CONSOLE_MSG

###############################################################################
# 2-3. 타겟 Connection 생성 (OCI콘솔 — 수동 확인)
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 2-3. 타겟 Connection 생성 (OCI콘솔 수동 작업) ---" | tee -a "$LOG"
cat <<'CONSOLE_MSG' | tee -a "$LOG"
[OCI콘솔] GoldenGate → Connections → Create Connection

[Target Connection]
  이름: TGT_DBCS_CONN
  유형: Oracle Database
  Host: ${TGT_DB_HOST}
  Port: 1521
  Service Name: ${TGT_DB_SERVICE}
  Username: GGADMIN
  Password: <password>
CONSOLE_MSG

###############################################################################
# 2-4. 네트워크 연결 테스트
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 2-4. 네트워크 연결 테스트 ---" | tee -a "$LOG"

# 소스 RDS 접근 테스트
echo "[소스] OCI GG에서 소스 RDS 접근 가능 여부 확인" | tee -a "$LOG"
echo "telnet ${SRC_DB_HOST} ${SRC_DB_PORT}" | tee -a "$LOG"
# telnet 테스트 (timeout 5초)
timeout 5 bash -c "echo > /dev/tcp/${SRC_DB_HOST}/${SRC_DB_PORT}" 2>&1 && \
    echo ">> 소스 RDS TCP 연결: 성공" | tee -a "$LOG" || \
    echo ">> 소스 RDS TCP 연결: 실패 — 방화벽/보안그룹 확인 필요" | tee -a "$LOG"

# sqlplus 소스 접속 테스트
echo "" | tee -a "$LOG"
echo "[소스] sqlplus 접속 테스트" | tee -a "$LOG"
${SRC_SQLPLUS_CONN} ${SRC_GG_USER}/${SRC_GG_PASS}@"${SRC_TNS}" <<'SQL_EOF' 2>&1 | tee -a "$LOG"
SELECT 'SOURCE_CONNECTION_OK' AS STATUS FROM DUAL;
EXIT;
SQL_EOF

# 타겟 DBCS 접근 테스트
echo "" | tee -a "$LOG"
echo "[타겟] OCI GG에서 타겟 DBCS 접근 가능 여부 확인" | tee -a "$LOG"
echo "telnet ${TGT_DB_HOST} ${TGT_DB_PORT}" | tee -a "$LOG"
timeout 5 bash -c "echo > /dev/tcp/${TGT_DB_HOST}/${TGT_DB_PORT}" 2>&1 && \
    echo ">> 타겟 DBCS TCP 연결: 성공" | tee -a "$LOG" || \
    echo ">> 타겟 DBCS TCP 연결: 실패 — 방화벽/보안그룹 확인 필요" | tee -a "$LOG"

# sqlplus 타겟 접속 테스트
echo "" | tee -a "$LOG"
echo "[타겟] sqlplus 접속 테스트" | tee -a "$LOG"
${TGT_SQLPLUS_CONN} ${TGT_GG_USER}/${TGT_GG_PASS}@"${TGT_TNS}" <<'SQL_EOF' 2>&1 | tee -a "$LOG"
SELECT 'TARGET_CONNECTION_OK' AS STATUS FROM DUAL;
EXIT;
SQL_EOF

###############################################################################
# 2-5. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 2-5. 결과 요약 ---" | tee -a "$LOG"
echo "기대값: sqlplus 접속 성공, SELECT 1 FROM DUAL 실행 가능" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 02 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
