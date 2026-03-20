-------------------------------------------------------------------------------
-- step01_gg_process_check.sql — GG 프로세스 검증 SQL queries (STEP 01, 28항목)
-- 실행 환경: [소스] / [타겟]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS} (소스)
--            ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS} (타겟)
-- 목적: GG 복제 프로세스의 정상 동작 및 설정 적합성 전수 검증
-- 담당: OCI GG 담당자, 소스/타겟 DBA
-- 예상 소요: 1시간
-- 참조: validation_plan.xlsx — 01_GG_Process (28항목)
-- 비고: 소스/타겟 구분 주석 확인 후 해당 DB에서 실행
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step01_gg_process_check.log

PROMPT =============================================
PROMPT STEP 01. GG 프로세스 검증 (01_GG_Process — 28항목)
PROMPT =============================================

PROMPT
PROMPT =============================================
PROMPT [1-1] Pre-Check 항목 (#1~9)
PROMPT =============================================

-- [검증항목 GG-001] ENABLE_GOLDENGATE_REPLICATION
PROMPT
PROMPT --- #1 ENABLE_GOLDENGATE_REPLICATION ---
PROMPT [소스] 실행
SELECT NAME, VALUE FROM V$PARAMETER
WHERE NAME = 'enable_goldengate_replication';
-- 기대값: TRUE

-- [검증항목 GG-002] Archive Log 모드
PROMPT
PROMPT --- #2 Archive Log 모드 ---
PROMPT [소스] 실행
SELECT LOG_MODE FROM V$DATABASE;
-- 기대값: ARCHIVELOG

-- [검증항목 GG-003] Supplemental Logging (MIN) 활성화
PROMPT
PROMPT --- #3 Supplemental Logging (MIN) 활성화 ---
PROMPT [소스] 실행
SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;
-- 기대값: YES

-- [검증항목 GG-004] PK 없는 테이블 ALL COLUMNS 로깅
PROMPT
PROMPT --- #4 PK 없는 테이블 ALL COLUMNS 로깅 ---
PROMPT [소스] 실행
SELECT
    (SELECT COUNT(*)
     FROM DBA_TABLES T
     WHERE T.OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
         'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS','MDSYS','OJVMSYS',
         'OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL','GGADMIN','GGS_TEMP','MIGRATION_USER')
     AND T.TEMPORARY = 'N' AND T.EXTERNAL = 'NO'
     AND NOT EXISTS (
         SELECT 1 FROM DBA_CONSTRAINTS C
         WHERE C.OWNER = T.OWNER AND C.TABLE_NAME = T.TABLE_NAME AND C.CONSTRAINT_TYPE = 'P'
     )
    ) AS NO_PK_TABLES,
    (SELECT COUNT(DISTINCT LOG_GROUP_TABLE)
     FROM DBA_LOG_GROUPS WHERE LOG_GROUP_TYPE = 'USER LOG GROUP'
    ) AS SUPLOG_APPLIED
FROM DUAL;
-- 기대값: NO_PK_TABLES = SUPLOG_APPLIED

-- [검증항목 GG-005] Redo Log 그룹/크기
PROMPT
PROMPT --- #5 Redo Log 그룹/크기 ---
PROMPT [소스] 실행
SELECT GROUP#, MEMBERS, BYTES/1024/1024 AS MB, STATUS FROM V$LOG;
-- 기대값: 최소 3그룹, 그룹당 500MB 이상

-- [검증항목 GG-006] GGADMIN 계정 권한
PROMPT
PROMPT --- #6 GGADMIN 계정 권한 ---
PROMPT [소스] / [타겟] 각각 실행
SELECT GRANTEE, PRIVILEGE FROM DBA_SYS_PRIVS WHERE GRANTEE = 'GGADMIN'
UNION ALL
SELECT GRANTEE, GRANTED_ROLE FROM DBA_ROLE_PRIVS WHERE GRANTEE = 'GGADMIN';

-- [검증항목 GG-007] RDS Redo Log 보존 기간
PROMPT
PROMPT --- #7 RDS Redo Log 보존 기간 ---
PROMPT [소스] 실행
SELECT NAME, VALUE FROM V$PARAMETER WHERE NAME LIKE 'archivelog%';
-- 기대값: 48시간 이상

-- [검증항목 GG-008] GG Deployment 버전 확인
PROMPT
PROMPT --- #8 GG Deployment 버전 확인 ---
PROMPT [OCI콘솔] GoldenGate → Deployments → 버전 확인
PROMPT Oracle 19c SE 지원 버전 확인 (콘솔에서 수동 확인)

-- [검증항목 GG-009] 네트워크 연결 (소스 → OCI GG 구간)
PROMPT
PROMPT --- #9 네트워크 연결 (소스 → OCI GG 구간) ---
PROMPT [로컬] OCI GG에서 소스 RDS 접근 가능 여부 — step01_gg_process_check.sh 에서 확인

PROMPT
PROMPT =============================================
PROMPT [1-6] 상시운영 항목 (#26~28) — SQL 부분
PROMPT =============================================

-- [검증항목 GG-026~028] 상시운영 — GGADMIN 비밀번호 만료 정책
PROMPT
PROMPT --- #28 GGADMIN 비밀번호 만료 정책 ---
PROMPT [타겟] 실행
SELECT U.USERNAME, P.LIMIT AS PASSWORD_LIFE_TIME
FROM DBA_USERS U
JOIN DBA_PROFILES P ON P.PROFILE = U.PROFILE AND P.RESOURCE_NAME = 'PASSWORD_LIFE_TIME'
WHERE U.USERNAME = 'GGADMIN';
-- 기대값: UNLIMITED 또는 만료 전 갱신 절차 수립

PROMPT
PROMPT =============================================
PROMPT STEP 01 SQL 검증 완료
PROMPT GG 프로세스 상태(#10~25) 검증은 step01_gg_process_check.sh 에서 GGSCI 명령으로 실행
PROMPT =============================================

SPOOL OFF
EXIT
