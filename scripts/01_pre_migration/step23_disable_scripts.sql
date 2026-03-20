-------------------------------------------------------------------------------
-- step23_disable_scripts.sql — FK/Trigger DISABLE 스크립트 생성 (STEP 23)
-- 실행 환경: [타겟]
-- 접속 정보: ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS}
-- 목적: 데이터 적재(impdp) 및 GG 복제 중 이중 실행 방지를 위한
--        Trigger/FK DISABLE 스크립트 사전 생성
-- 담당: 타겟 DBA
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 0
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET HEADING OFF
SET VERIFY OFF

SPOOL logs/step23_disable_scripts.log

PROMPT =============================================
PROMPT [23-1] Trigger DISABLE 스크립트 생성
PROMPT =============================================

-- disable_triggers.sql 생성
SPOOL logs/disable_triggers.sql
SELECT 'ALTER TRIGGER ' || OWNER || '.' || TRIGGER_NAME || ' DISABLE;'
FROM DBA_TRIGGERS
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY OWNER, TRIGGER_NAME;
SPOOL OFF

-- enable_triggers.sql 생성 (Cut-over 시 사용)
SPOOL logs/enable_triggers.sql
SELECT 'ALTER TRIGGER ' || OWNER || '.' || TRIGGER_NAME || ' ENABLE;'
FROM DBA_TRIGGERS
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY OWNER, TRIGGER_NAME;
SPOOL OFF

SPOOL logs/step23_disable_scripts.log APPEND
SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 1000

PROMPT =============================================
PROMPT [23-2] FK Constraint DISABLE 스크립트 생성
PROMPT =============================================

SET PAGESIZE 0
SET HEADING OFF
SET FEEDBACK OFF

-- disable_fk.sql 생성
SPOOL logs/disable_fk.sql
SELECT 'ALTER TABLE ' || OWNER || '.' || TABLE_NAME ||
       ' DISABLE CONSTRAINT ' || CONSTRAINT_NAME || ';'
FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY OWNER, TABLE_NAME;
SPOOL OFF

-- enable_fk.sql 생성 (Cut-over 시 사용)
SPOOL logs/enable_fk.sql
SELECT 'ALTER TABLE ' || OWNER || '.' || TABLE_NAME ||
       ' ENABLE CONSTRAINT ' || CONSTRAINT_NAME || ';'
FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R'
AND OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
)
ORDER BY OWNER, TABLE_NAME;
SPOOL OFF

SPOOL logs/step23_disable_scripts.log APPEND
SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 1000

PROMPT =============================================
PROMPT 생성된 스크립트 파일:
PROMPT   logs/disable_triggers.sql
PROMPT   logs/enable_triggers.sql
PROMPT   logs/disable_fk.sql
PROMPT   logs/enable_fk.sql
PROMPT =============================================
PROMPT STEP 23 DISABLE 스크립트 생성 완료
PROMPT =============================================

SPOOL OFF
EXIT
