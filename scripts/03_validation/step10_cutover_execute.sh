#!/usr/bin/env bash
set -euo pipefail
###############################################################################
# step10_cutover_execute.sh — Cut-over 실행 (STEP 10)
# 실행 환경: [소스] / [타겟] / [GG]
# 목적: 소스를 차단하고 타겟으로 완전 전환
# 담당: 마이그레이션 리더, 소스/타겟 DBA, OCI GG 담당자
# 예상 소요: 30분 이내 (목표)
# 주의: 이 스크립트는 단계별 수동 확인이 필요합니다.
#       각 단계 실행 후 결과를 확인하고 다음 단계로 진행하십시오.
###############################################################################
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step10_cutover_execute")
echo "[$(timestamp)] STEP 10 Cut-over 실행 시작" | tee "${LOG}"
echo "Cut-over 시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"

###############################################################################
# Step 1: 소스 DB 애플리케이션 세션 차단
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-1] Step 1: 소스 DB 애플리케이션 세션 차단" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo "[수동] AWS콘솔에서 RDS 보안그룹 → 인바운드 규칙 → TCP 1521 삭제 또는 비활성화" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

echo "--- 잔여 세션 확인 (0건 목표) ---" | tee -a "${LOG}"
${SRC_SQLPLUS_CONN} ${SRC_DBA_USER}/${SRC_DBA_PASS}@"${SRC_TNS}" <<'EOSQL' 2>&1 | tee -a "${LOG}"
SET PAGESIZE 100
SET LINESIZE 200
SET HEADING ON
SELECT COUNT(*) AS USER_SESSION_CNT
FROM V$SESSION
WHERE TYPE = 'USER' AND USERNAME != 'GGADMIN';
-- 기대값: 0건 (GGADMIN 제외)
EXIT
EOSQL

read -p "세션 차단 완료 확인 후 Enter를 누르세요 (Ctrl+C로 중단)..."

###############################################################################
# Step 2: 소스 DBMS_JOB BROKEN 처리
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-2] Step 2: 소스 DBMS_JOB BROKEN 처리" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

${SRC_SQLPLUS_CONN} ${SRC_DBA_USER}/${SRC_DBA_PASS}@"${SRC_TNS}" <<'EOSQL' 2>&1 | tee -a "${LOG}"
SET PAGESIZE 100
SET LINESIZE 200
SET HEADING ON
SET SERVEROUTPUT ON

-- BROKEN 처리 스크립트 생성 및 실행
BEGIN
    FOR r IN (SELECT JOB FROM DBA_JOBS WHERE BROKEN = 'N') LOOP
        DBMS_JOB.BROKEN(r.JOB, TRUE);
        DBMS_OUTPUT.PUT_LINE('JOB ' || r.JOB || ' BROKEN 처리 완료');
    END LOOP;
    COMMIT;
END;
/

-- 확인
SELECT JOB, BROKEN FROM DBA_JOBS;
-- 기대값: 모든 JOB BROKEN = 'Y'
EXIT
EOSQL

###############################################################################
# Step 3: 소스 CURRENT_SCN 최종 기록
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-3] Step 3: 소스 CURRENT_SCN 최종 기록" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

${SRC_SQLPLUS_CONN} ${SRC_DBA_USER}/${SRC_DBA_PASS}@"${SRC_TNS}" <<'EOSQL' 2>&1 | tee -a "${LOG}"
SET PAGESIZE 100
SET LINESIZE 200
SET HEADING ON
SELECT CURRENT_SCN, TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS CUT_TIME
FROM V$DATABASE;
EXIT
EOSQL

echo "" | tee -a "${LOG}"
echo "*** 위의 CURRENT_SCN과 CUT_TIME을 반드시 기록하십시오 ***" | tee -a "${LOG}"

###############################################################################
# Step 4: GG LAG = 0 확인 대기 (타임아웃: 30분)
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-4] Step 4: GG LAG = 0 확인 대기 (타임아웃: 30분)" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

TIMEOUT=1800  # 30분
INTERVAL=30   # 30초 간격
ELAPSED=0

while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
    echo "" | tee -a "${LOG}"
    echo "--- LAG 확인 (경과: ${ELAPSED}초) ---" | tee -a "${LOG}"

    echo "LAG EXTRACT ${GG_EXTRACT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"
    echo "LAG REPLICAT ${GG_REPLICAT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"
    echo "STATS REPLICAT ${GG_REPLICAT_NAME} TOTAL" | ${GGSCI} 2>&1 | tee -a "${LOG}"

    read -t ${INTERVAL} -p "LAG가 0초이면 Enter, 대기 중이면 ${INTERVAL}초 후 자동 재확인..." && break
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ ${ELAPSED} -ge ${TIMEOUT} ]; then
    echo "" | tee -a "${LOG}"
    echo "*** 경고: 30분 타임아웃 초과! 롤백 절차 검토 필요 ***" | tee -a "${LOG}"
    read -p "계속 진행하시겠습니까? (yes/no): " CONTINUE
    if [ "${CONTINUE}" != "yes" ]; then
        echo "Cut-over 중단." | tee -a "${LOG}"
        exit 1
    fi
fi

###############################################################################
# Step 5~6: Replicat 중지 및 HANDLECOLLISIONS 제거
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-5] Step 5~6: Replicat 중지 및 HANDLECOLLISIONS 확인" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

echo "STOP REPLICAT ${GG_REPLICAT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

echo "" | tee -a "${LOG}"
echo "--- Replicat 파라미터 확인 (HANDLECOLLISIONS 제거 여부) ---" | tee -a "${LOG}"
echo "VIEW PARAMS ${GG_REPLICAT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo "HANDLECOLLISIONS 라인이 남아있다면 EDIT PARAMS ${GG_REPLICAT_NAME} 으로 수동 제거하십시오." | tee -a "${LOG}"

read -p "HANDLECOLLISIONS 확인 완료 후 Enter를 누르세요..."

###############################################################################
# Step 7: 타겟 DB 최종 데이터 검증
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-6] Step 7: 타겟 DB 최종 데이터 검증" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

echo "핵심 테이블의 최신 데이터 및 Row Count를 소스와 비교 확인하십시오." | tee -a "${LOG}"
echo "아래 SQL을 타겟 DB에서 실행:" | tee -a "${LOG}"
echo "  SELECT MAX(<UPDATED_DATE_COL>) AS LATEST_DATA FROM <SCHEMA>.<KEY_TABLE>;" | tee -a "${LOG}"
echo "  SELECT COUNT(*) FROM <SCHEMA>.<KEY_TABLE>;" | tee -a "${LOG}"

read -p "데이터 검증 완료 후 Enter를 누르세요..."

###############################################################################
# Step 8a: Trigger 재활성화
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-7] Step 8a: Trigger 재활성화" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

${TGT_SQLPLUS_CONN} ${TGT_DBA_USER}/${TGT_DBA_PASS}@"${TGT_TNS}" <<'EOSQL' 2>&1 | tee -a "${LOG}"
SET PAGESIZE 1000
SET LINESIZE 300
SET HEADING ON
SET SERVEROUTPUT ON

-- Trigger ENABLE 스크립트 생성 및 실행
BEGIN
    FOR r IN (
        SELECT OWNER, TRIGGER_NAME
        FROM DBA_TRIGGERS
        WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
        AND STATUS = 'DISABLED'
        ORDER BY OWNER
    ) LOOP
        EXECUTE IMMEDIATE 'ALTER TRIGGER ' || r.OWNER || '.' || r.TRIGGER_NAME || ' ENABLE';
        DBMS_OUTPUT.PUT_LINE('ENABLED: ' || r.OWNER || '.' || r.TRIGGER_NAME);
    END LOOP;
END;
/

-- 확인: ENABLED Trigger 건수
SELECT COUNT(*) AS ENABLED_TRIGGER_CNT FROM DBA_TRIGGERS
WHERE STATUS = 'ENABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');

SELECT COUNT(*) AS DISABLED_TRIGGER_CNT FROM DBA_TRIGGERS
WHERE STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
-- 기대값: DISABLED = 0건
EXIT
EOSQL

###############################################################################
# Step 8b: FK Constraint 재활성화
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-7] Step 8b: FK Constraint 재활성화" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

${TGT_SQLPLUS_CONN} ${TGT_DBA_USER}/${TGT_DBA_PASS}@"${TGT_TNS}" <<'EOSQL' 2>&1 | tee -a "${LOG}"
SET PAGESIZE 1000
SET LINESIZE 300
SET HEADING ON
SET SERVEROUTPUT ON

-- FK ENABLE 스크립트 실행
BEGIN
    FOR r IN (
        SELECT OWNER, TABLE_NAME, CONSTRAINT_NAME
        FROM DBA_CONSTRAINTS
        WHERE CONSTRAINT_TYPE = 'R' AND STATUS = 'DISABLED'
        AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
        ORDER BY OWNER, TABLE_NAME
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'ALTER TABLE ' || r.OWNER || '.' || r.TABLE_NAME ||
                              ' ENABLE CONSTRAINT ' || r.CONSTRAINT_NAME;
            DBMS_OUTPUT.PUT_LINE('ENABLED FK: ' || r.OWNER || '.' || r.TABLE_NAME || '.' || r.CONSTRAINT_NAME);
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('*** FAILED FK: ' || r.OWNER || '.' || r.TABLE_NAME || '.' || r.CONSTRAINT_NAME || ' - ' || SQLERRM);
                DBMS_OUTPUT.PUT_LINE('    → Orphan Row 제거 후 재시도 필요');
        END;
    END LOOP;
END;
/

-- 확인: DISABLED FK 0건
SELECT COUNT(*) AS DISABLED_FK_CNT FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R' AND STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS');
EXIT
EOSQL

###############################################################################
# Step 8c: GG 프로세스 완전 중지 및 Sequence 재설정
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-7] Step 8c: GG 프로세스 완전 중지" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

echo "STOP EXTRACT ${GG_EXTRACT_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"
echo "STOP EXTRACT ${GG_PUMP_NAME}" | ${GGSCI} 2>&1 | tee -a "${LOG}"

echo "" | tee -a "${LOG}"
echo "--- 소스 Sequence 현재값 조회 ---" | tee -a "${LOG}"
${SRC_SQLPLUS_CONN} ${SRC_DBA_USER}/${SRC_DBA_PASS}@"${SRC_TNS}" <<'EOSQL' 2>&1 | tee -a "${LOG}"
SET PAGESIZE 1000
SET LINESIZE 300
SET HEADING ON
SELECT SEQUENCE_OWNER, SEQUENCE_NAME, LAST_NUMBER, CACHE_SIZE,
       LAST_NUMBER + (CACHE_SIZE * 10) AS SAFE_VALUE
FROM DBA_SEQUENCES
WHERE SEQUENCE_OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY SEQUENCE_OWNER, SEQUENCE_NAME;
EXIT
EOSQL

echo "" | tee -a "${LOG}"
echo "*** 타겟에서 Sequence 재설정 필요 ***" | tee -a "${LOG}"
echo "각 Sequence에 대해 아래 SQL을 타겟에서 실행:" | tee -a "${LOG}"
echo "  ALTER SEQUENCE <SCHEMA>.<SEQ_NAME> RESTART START WITH <SAFE_VALUE>;" | tee -a "${LOG}"
echo "  또는 (RESTART 미지원 시):" | tee -a "${LOG}"
echo "  ALTER SEQUENCE <SEQ_NAME> INCREMENT BY <DIFF>;" | tee -a "${LOG}"
echo "  SELECT <SEQ_NAME>.NEXTVAL FROM DUAL;" | tee -a "${LOG}"
echo "  ALTER SEQUENCE <SEQ_NAME> INCREMENT BY 1;" | tee -a "${LOG}"

read -p "Sequence 재설정 완료 후 Enter를 누르세요..."

###############################################################################
# Step 8d: DBMS_SCHEDULER JOB 활성화
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-7] Step 8d: DBMS_SCHEDULER JOB 활성화" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"

${TGT_SQLPLUS_CONN} ${TGT_DBA_USER}/${TGT_DBA_PASS}@"${TGT_TNS}" <<'EOSQL' 2>&1 | tee -a "${LOG}"
SET PAGESIZE 1000
SET LINESIZE 300
SET HEADING ON
SET SERVEROUTPUT ON

-- 전체 SCHEDULER JOB ENABLE
BEGIN
    FOR r IN (
        SELECT OWNER, JOB_NAME
        FROM DBA_SCHEDULER_JOBS
        WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
        AND STATE = 'DISABLED'
    ) LOOP
        DBMS_SCHEDULER.ENABLE(name => r.OWNER || '.' || r.JOB_NAME);
        DBMS_OUTPUT.PUT_LINE('ENABLED JOB: ' || r.OWNER || '.' || r.JOB_NAME);
    END LOOP;
END;
/

-- 전체 JOB ENABLE 후 상태 확인
SELECT JOB_NAME, STATE, NEXT_RUN_DATE FROM DBA_SCHEDULER_JOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, JOB_NAME;
EXIT
EOSQL

###############################################################################
# Step 8e: DB Link 연결 테스트
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-7] Step 8e: DB Link 연결 테스트" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "타겟에서 각 DB Link에 대해 아래 SQL을 실행:" | tee -a "${LOG}"
echo "  SELECT * FROM DUAL@<DB_LINK_NAME>;" | tee -a "${LOG}"
echo "  -- 기대값: DUMMY = 'X'" | tee -a "${LOG}"

###############################################################################
# Step 9~10: 애플리케이션 연결 전환 및 정상 동작 확인
###############################################################################
echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "[10-8] Step 9~10: 애플리케이션 연결 전환" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo "[인프라팀] DNS 변경 또는 애플리케이션 연결 문자열 타겟 OCI DBCS로 전환" | tee -a "${LOG}"
echo "[애플리케이션팀] 앱 서버 기동" | tee -a "${LOG}"
echo "[애플리케이션팀] 핵심 기능 Smoke Test 실행 (30분)" | tee -a "${LOG}"
echo "[모니터링] 에러 로그 모니터링 개시" | tee -a "${LOG}"

echo "" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
echo "Cut-over 완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "[$(timestamp)] STEP 10 Cut-over 실행 완료" | tee -a "${LOG}"
echo "결과 로그: ${LOG}" | tee -a "${LOG}"
echo "=============================================" | tee -a "${LOG}"
