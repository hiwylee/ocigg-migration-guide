-------------------------------------------------------------------------------
-- step19_recompile_invalid.sql — INVALID 객체 재컴파일 (STEP 19)
-- 실행 환경: [타겟]
-- 접속 정보: ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS} AS SYSDBA
-- 목적: impdp 후 의존성 오류로 INVALID 상태인 객체를 재컴파일하여 0건 달성
-- 담당: 타겟 DBA
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'
SET SERVEROUTPUT ON

SPOOL logs/step19_recompile_invalid.log

PROMPT =============================================
PROMPT [19-1] INVALID 객체 현황 확인 (재컴파일 전)
PROMPT =============================================

SELECT OWNER, OBJECT_TYPE, COUNT(*) AS INVALID_CNT
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
GROUP BY OWNER, OBJECT_TYPE
ORDER BY OWNER, OBJECT_TYPE;

PROMPT =============================================
PROMPT [19-2] 전체 사용자 스키마 일괄 재컴파일
PROMPT =============================================

BEGIN
    FOR u IN (
        SELECT USERNAME FROM DBA_USERS
        WHERE USERNAME NOT IN (
            'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
            'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER',
            'GSMUSER','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
            'ORDPLUGINS','ORDSYS','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA',
            'SYS$UMF','SYSBACKUP','SYSDG','SYSKM','SYSRAC','WMSYS','XDB','XS$NULL',
            'GGADMIN','GGS_TEMP','MIGRATION_USER'
        )
        AND ACCOUNT_STATUS = 'OPEN'
        ORDER BY USERNAME
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('Compiling schema: ' || u.USERNAME);
        DBMS_UTILITY.COMPILE_SCHEMA(schema => u.USERNAME, compile_all => FALSE);
    END LOOP;
END;
/

PROMPT =============================================
PROMPT [19-3] 재컴파일 후 INVALID 건수 확인
PROMPT 기대값: 0건
PROMPT =============================================

SELECT COUNT(*) AS INVALID_CNT
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
);

PROMPT =============================================
PROMPT 잔존 INVALID 상세 확인 (재컴파일 후에도 INVALID 존재 시)
PROMPT =============================================

SELECT OWNER, OBJECT_TYPE, OBJECT_NAME
FROM DBA_OBJECTS
WHERE STATUS = 'INVALID'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY OWNER, OBJECT_TYPE;

PROMPT =============================================
PROMPT 잔존 INVALID 수동 재컴파일 참고 (의존성 순서)
PROMPT   ALTER TYPE      <OWNER>.<TYPE_NAME>   COMPILE;
PROMPT   ALTER PACKAGE   <OWNER>.<PKG_NAME>    COMPILE;
PROMPT   ALTER PACKAGE   <OWNER>.<PKG_NAME>    COMPILE BODY;
PROMPT   ALTER PROCEDURE <OWNER>.<PROC_NAME>   COMPILE;
PROMPT   ALTER FUNCTION  <OWNER>.<FUNC_NAME>   COMPILE;
PROMPT   ALTER TRIGGER   <OWNER>.<TRG_NAME>    COMPILE;
PROMPT   ALTER VIEW      <OWNER>.<VIEW_NAME>   COMPILE;
PROMPT =============================================
PROMPT STEP 19 INVALID 객체 재컴파일 완료
PROMPT =============================================

SPOOL OFF
EXIT
