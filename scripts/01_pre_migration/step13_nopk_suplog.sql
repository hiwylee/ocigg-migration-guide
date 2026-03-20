-------------------------------------------------------------------------------
-- step13_nopk_suplog.sql — PK 없는 테이블 ALL COLUMNS 로깅 (STEP 13)
-- 실행 환경: [소스]
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS}
-- 목적: PK 없는 테이블의 UPDATE/DELETE를 GG가 정확히 추적하기 위해 ALL COLUMNS 로깅 필요
-- 담당: 소스 DBA
-- SE 제약: PK 없는 테이블에 ALL COLUMNS 로깅 미설정 시 Replicat ABEND 발생
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step13_nopk_suplog.log

PROMPT =============================================
PROMPT [13-1] 적용 대상 확인 및 스크립트 생성
PROMPT PK 없는 테이블에 ALL COLUMNS 로깅 적용 스크립트 생성
PROMPT =============================================

-- 결과를 파일로 저장: suplog_nopk.sql
SPOOL logs/suplog_nopk.sql
SELECT 'ALTER TABLE ' || T.OWNER || '.' || T.TABLE_NAME ||
       ' ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;'
FROM DBA_TABLES T
WHERE T.OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER',
    'GSMUSER','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','ORACLE_OCM','ORDDATA',
    'ORDPLUGINS','ORDSYS','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA',
    'SYS$UMF','SYSBACKUP','SYSDG','SYSKM','SYSRAC','WMSYS','XDB','XS$NULL',
    'GGADMIN','GGS_TEMP','MIGRATION_USER'
)
AND T.TEMPORARY = 'N'
AND T.EXTERNAL = 'NO'
AND NOT EXISTS (
    SELECT 1 FROM DBA_CONSTRAINTS C
    WHERE C.OWNER = T.OWNER AND C.TABLE_NAME = T.TABLE_NAME
    AND C.CONSTRAINT_TYPE = 'P'
)
ORDER BY T.OWNER, T.TABLE_NAME;
SPOOL OFF

PROMPT =============================================
PROMPT [13-2] 생성된 스크립트 실행
PROMPT =============================================

-- 생성된 스크립트 실행
@logs/suplog_nopk.sql
COMMIT;

SPOOL logs/step13_nopk_suplog.log APPEND

PROMPT =============================================
PROMPT [13-3] 적용 결과 확인
PROMPT PK 없는 테이블 수 vs 적용된 ALL COLUMNS 로깅 수 비교
PROMPT =============================================

SELECT
    (SELECT COUNT(*) FROM DBA_TABLES T
     WHERE T.OWNER NOT IN (
         'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
         'DBSFWUSER','DVSYS','EXFSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
         'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB'
     )
     AND TEMPORARY='N' AND EXTERNAL='NO'
     AND NOT EXISTS (
         SELECT 1 FROM DBA_CONSTRAINTS C
         WHERE C.OWNER=T.OWNER AND C.TABLE_NAME=T.TABLE_NAME
         AND C.CONSTRAINT_TYPE='P'
     )
    ) AS NO_PK_TABLES,
    (SELECT COUNT(DISTINCT OWNER || '.' || LOG_GROUP_TABLE)
     FROM DBA_LOG_GROUPS
     WHERE LOG_GROUP_TYPE = 'USER LOG GROUP'
    ) AS SUPLOG_APPLIED
FROM DUAL;

PROMPT --- LOG_GROUP_TYPE 별 집계 ---

SELECT LOG_GROUP_TYPE, COUNT(*) FROM DBA_LOG_GROUP_COLUMNS
GROUP BY LOG_GROUP_TYPE;

PROMPT =============================================
PROMPT STEP 13 PK 없는 테이블 ALL COLUMNS 로깅 완료
PROMPT =============================================

SPOOL OFF
EXIT
