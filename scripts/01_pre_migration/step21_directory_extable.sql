-------------------------------------------------------------------------------
-- step21_directory_extable.sql — Directory/External Table 처리 (STEP 21)
-- 실행 환경: [타겟]
-- 접속 정보: ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS}
-- 목적: 소스의 Directory Object를 타겟 OCI 환경에 맞게 재생성
-- 담당: 타겟 DBA
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step21_directory_extable.log

PROMPT =============================================
PROMPT [21-1] 소스 Directory 목록 기반 타겟 재생성
PROMPT ※ 소스에서 수집한 목록 (STEP 01) 활용
PROMPT =============================================

-- [소스] Directory 목록 (STEP 01에서 수집한 목록 활용)
SELECT DIRECTORY_NAME, DIRECTORY_PATH FROM DBA_DIRECTORIES
ORDER BY DIRECTORY_NAME;

PROMPT =============================================
PROMPT OCI DBCS 경로로 재생성
PROMPT ※ <DIR_NAME>, <DB_NAME>, <SCHEMA_USER> 를 실제 값으로 교체
PROMPT =============================================

-- [타겟] OCI DBCS 경로로 재생성
-- CREATE OR REPLACE DIRECTORY <DIR_NAME> AS '/u01/app/oracle/admin/<DB_NAME>/dpdump/';
-- GRANT READ, WRITE ON DIRECTORY <DIR_NAME> TO <SCHEMA_USER>;
-- (소스에서 해당 Directory에 접근하던 스키마에 동일하게 권한 부여)

PROMPT =============================================
PROMPT [21-2] External Table 처리
PROMPT =============================================

-- [타겟] External Table 목록 확인
SELECT OWNER, TABLE_NAME, DEFAULT_DIRECTORY_NAME
FROM DBA_EXTERNAL_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS'
);

PROMPT =============================================
PROMPT External Table이 존재하는 경우:
PROMPT   1. 외부 파일을 OCI Object Storage 또는 DBCS 서버로 이관
PROMPT   2. 타겟 Directory 경로를 OCI 환경에 맞게 수정
PROMPT   3. External Table SELECT 테스트 수행
PROMPT =============================================
PROMPT STEP 21 Directory/External Table 처리 완료
PROMPT =============================================

SPOOL OFF
EXIT
