#!/usr/bin/env bash
set -euo pipefail
###############################################################################
# step12_stabilization.sh — 안정화 모니터링 (STEP 12)
# 실행 환경: [타겟] / [GG]
# 목적: Cut-over 후 D+14일까지 시스템 안정성 모니터링
# 담당: 타겟 DBA, OCI GG 담당자
# 기간: D+1 ~ D+14
###############################################################################
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step12_stabilization")
echo "[$(timestamp)] STEP 12 안정화 모니터링 시작" | tee "${LOG}"

###############################################################################
# 12-1. 상시 모니터링 Top 10 체크리스트 출력
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[12-1] 상시 모니터링 Top 10 체크리스트" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo " 1. Extract/Replicat LAG 상시 모니터링 — LAG > 30초 즉시 알람 → 원인 분석" | tee -a "${LOG}"
echo " 2. PK 없는 테이블 ALL COLUMNS Logging 유지 — 신규 테이블 생성 시 즉시 적용" | tee -a "${LOG}"
echo " 3. Sequence GAP 누적 관리 — 주간 Gap 확인, 필요 시 재설정" | tee -a "${LOG}"
echo " 4. Trigger 이중 실행 방지 — GGADMIN 세션 Trigger 예외 로직 확인" | tee -a "${LOG}"
echo " 5. DDL Replication ABEND 관리 — 미지원 DDL 수동 처리 즉시 적용" | tee -a "${LOG}"
echo " 6. RDS Redo Log 보존 기간 관리 — 최소 24h 이상 유지" | tee -a "${LOG}"
echo " 7. GGADMIN 비밀번호 만료 모니터링 — 만료 30일 전 알람 → 즉시 갱신" | tee -a "${LOG}"
echo " 8. LOB 컬럼 Trail File 용량 급증 — Object Storage 80% 초과 시 알람" | tee -a "${LOG}"
echo " 9. Constraint DISABLED 상태 정기 점검 — 주간 점검, Disabled 발견 시 원인 분석" | tee -a "${LOG}"
echo "10. NLS 파라미터/타임존 변경 금지 — 변경 금지 정책, 승인 프로세스 필수" | tee -a "${LOG}"

###############################################################################
# 12-2. Discard 파일 일일 점검
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[12-2] Discard 파일 일일 점검" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

echo "" | tee -a "${LOG}"
echo "--- Replicat Discard 확인 (매일 1회 이상 실행) ---" | tee -a "${LOG}"
echo "VIEW DISCARD ${GG_REPLICAT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo "Discard 레코드 > 0건 시: 원인 분석 → 재적용 또는 데이터 수정 후 확인" | tee -a "${LOG}"

###############################################################################
# 12-3. 타겟 DB 상태 모니터링
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[12-3] 타겟 DB 상태 모니터링" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

${TGT_SQLPLUS_CONN} ${TGT_DBA_USER}/${TGT_DBA_PASS}@"${TGT_TNS}" <<'EOSQL' 2>&1 | tee -a "${LOG}"
SET PAGESIZE 1000
SET LINESIZE 300
SET HEADING ON
SET COLSEP '|'

PROMPT --- DB 인스턴스 상태 ---
SELECT INSTANCE_NAME, STATUS, DATABASE_STATUS, HOST_NAME FROM V$INSTANCE;

PROMPT --- INVALID 객체 확인 ---
SELECT COUNT(*) AS INVALID_CNT FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT --- UNUSABLE 인덱스 확인 ---
SELECT COUNT(*) AS UNUSABLE_IDX_CNT FROM DBA_INDEXES
WHERE STATUS NOT IN ('VALID','N/A')
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT --- DISABLED FK 확인 ---
SELECT COUNT(*) AS DISABLED_FK_CNT FROM DBA_CONSTRAINTS
WHERE STATUS = 'DISABLED' AND CONSTRAINT_TYPE = 'R'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT --- DISABLED Trigger 확인 ---
SELECT COUNT(*) AS DISABLED_TRIGGER_CNT FROM DBA_TRIGGERS
WHERE STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

PROMPT --- DISABLED SCHEDULER JOB 확인 ---
SELECT JOB_NAME, STATE FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
AND STATE = 'DISABLED';

PROMPT --- Tablespace 사용량 확인 ---
SELECT TABLESPACE_NAME,
       ROUND(SUM(BYTES)/1024/1024/1024, 2) AS TOTAL_GB,
       ROUND(SUM(NVL(FREE_BYTES,0))/1024/1024/1024, 2) AS FREE_GB,
       ROUND(SUM(NVL(FREE_BYTES,0))/SUM(BYTES)*100, 1) AS FREE_PCT
FROM (
    SELECT D.TABLESPACE_NAME, D.BYTES, F.FREE_BYTES
    FROM (SELECT TABLESPACE_NAME, SUM(BYTES) AS BYTES FROM DBA_DATA_FILES GROUP BY TABLESPACE_NAME) D
    LEFT JOIN (SELECT TABLESPACE_NAME, SUM(BYTES) AS FREE_BYTES FROM DBA_FREE_SPACE GROUP BY TABLESPACE_NAME) F
    ON D.TABLESPACE_NAME = F.TABLESPACE_NAME
)
GROUP BY TABLESPACE_NAME
ORDER BY FREE_PCT;

PROMPT --- GGADMIN 비밀번호 만료 확인 ---
SELECT U.USERNAME, U.EXPIRY_DATE, P.LIMIT AS PASSWORD_LIFE_TIME
FROM DBA_USERS U
JOIN DBA_PROFILES P ON P.PROFILE = U.PROFILE AND P.RESOURCE_NAME = 'PASSWORD_LIFE_TIME'
WHERE U.USERNAME = 'GGADMIN';

PROMPT --- Alert Log 최근 오류 확인 (수동) ---
PROMPT V$DIAG_ALERT_EXT 또는 adrci 로 최근 ORA- 오류 확인 필요
EXIT
EOSQL

###############################################################################
# 12-4. GG 프로세스 상태 확인 (롤백 대비 기간 중)
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[12-4] GG 프로세스 상태 확인 (롤백 대비 기간 중에만)" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

echo "GG가 아직 운영 중인 경우 아래를 확인:" | tee -a "${LOG}"
echo "  STATUS EXTRACT ${GG_EXTRACT_NAME}" | tee -a "${LOG}"
echo "  STATUS REPLICAT ${GG_REPLICAT_NAME}" | tee -a "${LOG}"
echo "  LAG EXTRACT ${GG_EXTRACT_NAME}" | tee -a "${LOG}"
echo "  LAG REPLICAT ${GG_REPLICAT_NAME}" | tee -a "${LOG}"

###############################################################################
# 12-5. 일일 모니터링 기록표
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[12-5] 일일 모니터링 기록표" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo "| 날짜   | EXT1 LAG | REP1 LAG | Discard 건수 | ABEND | 특이사항 | 확인자 |" | tee -a "${LOG}"
echo "|--------|---------|---------|------------|-------|---------|--------|" | tee -a "${LOG}"
echo "| D+1    |         |         |            |       |         |        |" | tee -a "${LOG}"
echo "| D+2    |         |         |            |       |         |        |" | tee -a "${LOG}"
echo "| D+3    |         |         |            |       |         |        |" | tee -a "${LOG}"
echo "| D+7    |         |         |            |       |         |        |" | tee -a "${LOG}"
echo "| D+14   |         |         |            |       |         |        |" | tee -a "${LOG}"

###############################################################################
# 12-6. 소스 RDS 유지 및 종료 계획
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[12-6] 소스 RDS 유지 및 종료 계획" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo "| 일정    | 작업                                                | 담당자 | 완료 서명 |" | tee -a "${LOG}"
echo "|---------|-----------------------------------------------------|--------|---------|" | tee -a "${LOG}"
echo "| D+1~14  | 소스 RDS 유지 (롤백 대비)                              |        |         |" | tee -a "${LOG}"
echo "| D+7     | 타겟 안정화 확인 후 소스 → Read-Only 전환 검토             |        |         |" | tee -a "${LOG}"
echo "| D+14    | 이상 없음 확인 시 소스 RDS 종료 및 비용 절감               |        |         |" | tee -a "${LOG}"
echo "| 최종    | OCI GG Deployment 종료 또는 상시 동기화 모드 결정         |        |         |" | tee -a "${LOG}"

###############################################################################
# 12-7. 롤백 결정 트리거 조건
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[12-7] 롤백 결정 트리거 조건" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo "| 조건                                    | 심각도    | 결정 타임아웃 | 담당자          |" | tee -a "${LOG}"
echo "|-----------------------------------------|----------|-------------|----------------|" | tee -a "${LOG}"
echo "| 애플리케이션 심각한 기능 오류               | 즉시     | 30분 이내    | 마이그레이션 리더 |" | tee -a "${LOG}"
echo "| 데이터 무결성 문제 발견                     | 즉시     | 30분 이내    | 마이그레이션 리더 |" | tee -a "${LOG}"
echo "| 타겟 DB 성능 소스 대비 30% 이상 저하         | 1시간 이내| 1시간       | 마이그레이션 리더 |" | tee -a "${LOG}"
echo "| Cut-over 후 4시간 경과, 이슈 미해결         | 자동 결정 | —           | 마이그레이션 리더 |" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo "롤백 절차: plan/migration_plan.md > 롤백 계획 섹션 참조" | tee -a "${LOG}"

echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[$(timestamp)] STEP 12 안정화 모니터링 완료" | tee -a "${LOG}"
echo "결과 로그: ${LOG}" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
