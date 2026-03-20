-------------------------------------------------------------------------------
-- step22_special_objects.sql — 특수 객체 처리 (STEP 22)
-- 실행 환경: [타겟]
-- 접속 정보: ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS}
-- 목적: GG가 복제하지 않는 특수 객체(MV, DB Link, DBMS_JOB)를 타겟에서 수동 준비
-- 담당: 타겟 DBA + 애플리케이션 담당
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'
SET SERVEROUTPUT ON

SPOOL logs/step22_special_objects.log

PROMPT =============================================
PROMPT [22-1] Materialized View (MV) 처리
PROMPT OCI GG는 MV 자체를 복제하지 않음.
PROMPT Cut-over 시점 이후 타겟에서 COMPLETE REFRESH 수행 예정
PROMPT =============================================

-- [타겟] MV 목록 및 상태 확인 (impdp로 MV 컨테이너 테이블만 생성된 상태)
SELECT OWNER, MVIEW_NAME, REFRESH_METHOD, STALENESS
FROM DBA_MVIEWS
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS'
);

PROMPT =============================================
PROMPT [22-2] DB Link 처리
PROMPT =============================================

-- [소스] DB Link 목록 (소스 환경 기준)
SELECT OWNER, DB_LINK, USERNAME, HOST FROM DBA_DB_LINKS
ORDER BY OWNER, DB_LINK;

PROMPT --- 네트워크 환경에 맞게 수정하여 재생성 ---
PROMPT ※ <LINK_NAME>, <USER>, <PASSWORD>, <OCI_TNS_STRING> 을 실제 값으로 교체

-- [타겟] 네트워크 환경에 맞게 수정하여 재생성
-- TNS/EZConnect 문자열을 OCI 환경 기준으로 변경
-- CREATE DATABASE LINK <LINK_NAME>
--     CONNECT TO <USER> IDENTIFIED BY <PASSWORD>
--     USING '<OCI_TNS_STRING>';
--
-- 연결 테스트
-- SELECT SYSDATE FROM DUAL@<LINK_NAME>;

PROMPT =============================================
PROMPT [22-3] DBMS_JOB -> DBMS_SCHEDULER 전환 준비
PROMPT SE 19c: DBMS_JOB은 Deprecated -- DBMS_SCHEDULER로 전환 권장
PROMPT =============================================

-- [소스] DBMS_JOB 전체 목록 확인
SELECT JOB, LOG_USER, WHAT, INTERVAL, BROKEN, NEXT_DATE
FROM DBA_JOBS ORDER BY JOB;

PROMPT --- DBMS_SCHEDULER JOB 생성 예시 ---
PROMPT ※ 소스 INTERVAL 표현식 기반으로 변환
PROMPT ※ JOB은 Cut-over 시까지 DISABLED 상태 유지

-- [타겟] DBMS_SCHEDULER JOB 생성 (소스 INTERVAL 표현식 기반으로 변환)
-- 예시:
-- BEGIN
--     DBMS_SCHEDULER.CREATE_JOB(
--         job_name        => '<SCHEMA>.<JOB_NAME>',
--         job_type        => 'PLSQL_BLOCK',
--         job_action      => '<소스 WHAT 내용>',
--         repeat_interval => 'FREQ=<DAILY/HOURLY/...>; INTERVAL=<n>',
--         enabled         => FALSE,   -- 마이그레이션 완료 후 ENABLE
--         comments        => '소스 DBMS_JOB #<JOB_NO> 전환'
--     );
-- END;
-- /

PROMPT =============================================
PROMPT STEP 22 특수 객체 처리 완료
PROMPT =============================================

SPOOL OFF
EXIT
