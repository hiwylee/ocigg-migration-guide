#!/usr/bin/env bash
###############################################################################
# step13_stats_import.sh — 통계정보 Import
# 실행 환경: [타겟]
# 목적: 소스에서 Export한 통계정보를 타겟에 Import하여 옵티마이저 계획 정합성 확보
# 담당: 타겟 DBA
# 예상 소요: 30분 ~ 1시간
#
# 전제: 01.pre_migration.md STEP 24에서 소스의 STATS_EXPORT_TABLE을
#       stats_export.dmp로 Export하고 OCI Object Storage에 업로드 완료
#       (STEP 11에서 타겟 다운로드 완료)
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../config/env.sh"

LOG=$(log_file "step13_stats_import")
echo "=== STEP 13. 통계정보 Import (옵션 A) ===" | tee "$LOG"
echo "시작 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

###############################################################################
# 13-1. STATS_EXPORT_TABLE impdp Import
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 13-1. STATS_EXPORT_TABLE impdp Import ---" | tee -a "$LOG"

# 통계 스테이징 테이블 Import
impdp ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" \
    TABLES=${TGT_MIG_USER}.STATS_EXPORT_TABLE \
    DUMPFILE=stats_export.dmp \
    LOGFILE=stats_import.log \
    TABLE_EXISTS_ACTION=REPLACE \
    DIRECTORY=${IMPDP_DIR} \
    2>&1 | tee -a "$LOG"

###############################################################################
# 13-2. 전체 DB 통계 Import
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 13-2. 전체 DB 통계 Import ---" | tee -a "$LOG"

${TGT_SQLPLUS_CONN} ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" <<'SQL_EOF' 2>&1 | tee -a "$LOG"
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON
SET FEEDBACK ON

PROMPT 전체 DB 통계 일괄 Import (소스 통계정보 타겟에 적용)

BEGIN
    DBMS_STATS.IMPORT_DATABASE_STATS(
        stattab => 'STATS_EXPORT_TABLE',
        statown => 'MIGRATION_USER',
        force   => TRUE     -- 기존 통계 덮어쓰기
    );
END;
/

PROMPT >> IMPORT_DATABASE_STATS 완료
EXIT;
SQL_EOF

###############################################################################
# 13-3. 통계 Import 결과 확인
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 13-3. 통계 Import 결과 확인 ---" | tee -a "$LOG"

${TGT_SQLPLUS_CONN} ${TGT_MIG_USER}/${TGT_MIG_PASS}@"${TGT_TNS}" <<'SQL_EOF' 2>&1 | tee -a "$LOG"
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 200
SET PAGESIZE 50
SET FEEDBACK ON

SPOOL /tmp/step13_stats_import_result.log

PROMPT 스키마별 통계 존재 현황:
SELECT OWNER,
       COUNT(*) AS TABLE_CNT,
       SUM(CASE WHEN LAST_ANALYZED IS NULL THEN 1 ELSE 0 END) AS NO_STATS_CNT
FROM DBA_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL'
)
GROUP BY OWNER
ORDER BY NO_STATS_CNT DESC;
-- 기대값: 모든 스키마 NO_STATS_CNT = 0

SPOOL OFF
EXIT;
SQL_EOF

###############################################################################
# 13-4. 결과 요약
###############################################################################
echo "" | tee -a "$LOG"
echo "--- 13-4. 결과 요약 ---" | tee -a "$LOG"
echo "  - STATS_EXPORT_TABLE impdp 완료 확인" | tee -a "$LOG"
echo "  - IMPORT_DATABASE_STATS 완료 확인" | tee -a "$LOG"
echo "  - 통계 없는 테이블 0건 (NO_STATS_CNT = 0) 확인" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "로그 파일: ${LOG}" | tee -a "$LOG"
echo ">> STEP 13 완료 서명: __________________ 일시: __________________" | tee -a "$LOG"
