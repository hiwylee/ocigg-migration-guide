-------------------------------------------------------------------------------
-- step03_data_validation.sql — 데이터 정합성 검증 (STEP 03, 25항목)
-- 실행 환경: [양쪽] — 소스/타겟 동일 쿼리 실행 후 결과 비교
-- 접속 정보: ${SRC_DBA_USER}/${SRC_DBA_PASS}@${SRC_TNS} (소스)
--            ${TGT_DBA_USER}/${TGT_DBA_PASS}@${TGT_TNS} (타겟)
-- 목적: 소스/타겟 데이터 내용이 GG 복제 기준으로 일치하는지 검증
-- 담당: 소스/타겟 DBA, 비즈니스 담당
-- 예상 소요: 3~4시간
-- 참조: validation_plan.xlsx — 03_Data_Validation (25항목)
-- 비고: Row Count 비교 기준 — GG 실시간 동기화 중이므로 ±수 건 오차 허용
--       단, 1% 이상 차이 발생 시 WARN 처리 후 원인 분석 필수
-------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 1000
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK ON
SET HEADING ON
SET COLSEP '|'

SPOOL logs/step03_data_validation.log

PROMPT =============================================
PROMPT STEP 03. 데이터 정합성 검증 (03_Data_Validation — 25항목)
PROMPT =============================================

PROMPT
PROMPT =============================================
PROMPT [3-1] 전체 Row Count 비교 (#1~3)
PROMPT =============================================

-- [검증항목 DV-001~003] 전체 Row Count 비교
PROMPT
PROMPT --- 핵심 테이블 Row Count 비교 스크립트 생성 ---
PROMPT [양쪽] 아래 생성된 SQL 문을 소스/타겟에서 각각 실행
SELECT 'SELECT ''' || OWNER || '.' || TABLE_NAME || ''' AS TBL, COUNT(*) AS CNT FROM '
       || OWNER || '.' || TABLE_NAME || ';'
FROM DBA_TABLES
WHERE OWNER NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB','XS$NULL',
    'GGADMIN','GGS_TEMP','MIGRATION_USER'
)
ORDER BY OWNER, TABLE_NAME;
-- 생성된 스크립트 실행 후 소스/타겟 비교

-- [검증항목 DV-002] 대용량 테이블 파티션 단위 비교
PROMPT
PROMPT --- 대용량 테이블 파티션 단위 비교 ---
SELECT OWNER, TABLE_NAME, PARTITION_NAME, NUM_ROWS
FROM DBA_TAB_PARTITIONS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
AND NUM_ROWS > 10000000
ORDER BY OWNER, TABLE_NAME, PARTITION_POSITION;

PROMPT
PROMPT =============================================
PROMPT [3-2] Checksum 비교 (#4~6)
PROMPT =============================================

-- [검증항목 DV-004~006] Checksum 비교
PROMPT
PROMPT --- ORA_HASH 기반 체크섬 (ROWID 절대 사용 금지 — 소스/타겟 ROWID 다름) ---
PROMPT PK + 핵심 컬럼 기반 체크섬 — 아래 템플릿을 테이블별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT
PROMPT     COUNT(*) AS CNT,
PROMPT     SUM(ORA_HASH(
PROMPT         TO_CHAR(<PK_COL>) || '|' ||
PROMPT         TO_CHAR(<COL1>)   || '|' ||
PROMPT         TO_CHAR(<COL2>)
PROMPT     )) AS CHECKSUM
PROMPT FROM <SCHEMA>.<TABLE_NAME>;
PROMPT -- 소스/타겟 CNT와 CHECKSUM 모두 일치해야 함

PROMPT
PROMPT --- 핵심 테이블 집계 비교 ---
PROMPT 아래 템플릿을 핵심 테이블별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT
PROMPT     SUM(<AMOUNT_COL>) AS TOTAL_SUM,
PROMPT     MAX(<AMOUNT_COL>) AS MAX_VAL,
PROMPT     MIN(<AMOUNT_COL>) AS MIN_VAL,
PROMPT     COUNT(DISTINCT <KEY_COL>) AS DISTINCT_KEY_CNT
PROMPT FROM <SCHEMA>.<TABLE_NAME>;

PROMPT
PROMPT =============================================
PROMPT [3-3] 샘플 데이터 비교 (#7~9)
PROMPT =============================================

-- [검증항목 DV-007~009] 샘플 데이터 비교
PROMPT
PROMPT --- 최신 1000건 비교 (PK 기준 정렬) ---
PROMPT 아래 템플릿을 테이블별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT <PK_COL>, <COL1>, <COL2>, <UPDATED_DATE>
PROMPT FROM <SCHEMA>.<TABLE_NAME>
PROMPT ORDER BY <UPDATED_DATE> DESC
PROMPT FETCH FIRST 1000 ROWS ONLY;

PROMPT
PROMPT --- NULL 비율 비교 (핵심 컬럼 대상) ---
PROMPT 아래 템플릿을 테이블별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT
PROMPT     COUNT(*) AS TOTAL,
PROMPT     SUM(CASE WHEN <COL> IS NULL THEN 1 ELSE 0 END) AS NULL_CNT,
PROMPT     ROUND(SUM(CASE WHEN <COL> IS NULL THEN 1 ELSE 0 END)/COUNT(*)*100,2) AS NULL_PCT
PROMPT FROM <SCHEMA>.<TABLE_NAME>;

PROMPT
PROMPT =============================================
PROMPT [3-4] LOB 검증 (#10~14)
PROMPT =============================================

-- [검증항목 DV-010~014] LOB 검증
PROMPT
PROMPT --- LOB 컬럼 보유 테이블 목록 ---
SELECT OWNER, TABLE_NAME, COLUMN_NAME, SEGMENT_NAME, SECUREFILE
FROM DBA_LOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP')
ORDER BY OWNER, TABLE_NAME;

PROMPT
PROMPT --- LOB 건수 및 크기 비교 — 아래 템플릿을 LOB 테이블별로 수정하여 실행 ---
PROMPT
PROMPT 예시:
PROMPT SELECT COUNT(*) AS ROW_CNT,
PROMPT        SUM(DBMS_LOB.GETLENGTH(<LOB_COL>)) AS TOTAL_BYTES
PROMPT FROM <SCHEMA>.<TABLE_NAME>;

PROMPT
PROMPT --- EMPTY_LOB vs NULL 처리 일관성 — 아래 템플릿을 LOB 테이블별로 수정하여 실행 ---
PROMPT
PROMPT 예시:
PROMPT SELECT
PROMPT     SUM(CASE WHEN <LOB_COL> IS NULL THEN 1 ELSE 0 END) AS NULL_CNT,
PROMPT     SUM(CASE WHEN DBMS_LOB.GETLENGTH(<LOB_COL>) = 0 THEN 1 ELSE 0 END) AS EMPTY_CNT
PROMPT FROM <SCHEMA>.<TABLE_NAME>;

PROMPT
PROMPT --- BasicFile / SecureFile 전환 여부 확인 ---
PROMPT [타겟] 실행
SELECT OWNER, TABLE_NAME, COLUMN_NAME, SECUREFILE
FROM DBA_LOBS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');
-- 소스와 동일한 유형(SECUREFILE YES/NO) 유지 여부 확인

PROMPT
PROMPT =============================================
PROMPT [3-5] 데이터 타입 특이사항 검증 (#15~20)
PROMPT =============================================

-- [검증항목 DV-015~020] 데이터 타입 특이사항
PROMPT
PROMPT --- DATE 컬럼 시간 정보 유실 여부 확인 ---
PROMPT 아래 템플릿을 DATE 컬럼 보유 핵심 테이블별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT TO_CHAR(<DATE_COL>, 'YYYY-MM-DD HH24:MI:SS')
PROMPT FROM <SCHEMA>.<TABLE_NAME>
PROMPT WHERE <DATE_COL> > SYSDATE - 7
PROMPT FETCH FIRST 100 ROWS ONLY;
PROMPT -- 시:분:초가 00:00:00으로 유실되지 않았는지 확인

PROMPT
PROMPT --- TIMESTAMP WITH TIME ZONE 확인 ---
SELECT DBTIMEZONE FROM DUAL;
SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
WHERE PARAMETER = 'NLS_TIMESTAMP_TZ_FORMAT';
-- 소스/타겟 동일 확인

PROMPT
PROMPT --- XMLTYPE 스토리지 방식 확인 ---
SELECT OWNER, TABLE_NAME, COLUMN_NAME, STORAGE_TYPE
FROM DBA_XML_TAB_COLS
WHERE OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP');

PROMPT
PROMPT --- ROWID 의존 소스 코드 식별 ---
PROMPT [타겟] 실행 — 애플리케이션 레벨 점검 필요
SELECT OWNER, NAME, TYPE, LINE, TEXT
FROM DBA_SOURCE
WHERE UPPER(TEXT) LIKE '%ROWID%'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS',
    'DBSFWUSER','DVSYS','GGSYS','GSMADMIN_INTERNAL','LBACSYS',
    'MDSYS','OJVMSYS','OLAPSYS','ORDDATA','ORDSYS','WMSYS','XDB')
ORDER BY OWNER, NAME, LINE;
-- ROWID 의존 PL/SQL 오브젝트 식별 → 애플리케이션 팀 확인 요청

PROMPT
PROMPT =============================================
PROMPT [3-6] NLS 검증 (#21~23)
PROMPT =============================================

-- [검증항목 DV-021~023] NLS 검증
PROMPT
PROMPT --- NLS 데이터베이스 파라미터 비교 ---
SELECT PARAMETER, VALUE FROM NLS_DATABASE_PARAMETERS
ORDER BY PARAMETER;
-- 소스/타겟 동일 확인

PROMPT
PROMPT --- 한글/특수문자 샘플 데이터 확인 ---
PROMPT 아래 템플릿을 한글 컬럼 보유 테이블별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT <KOREAN_COL>,
PROMPT        LENGTHB(<KOREAN_COL>) AS BYTE_LEN,
PROMPT        LENGTH(<KOREAN_COL>) AS CHAR_LEN
PROMPT FROM <SCHEMA>.<TABLE_NAME>
PROMPT WHERE LENGTHB(<KOREAN_COL>) != LENGTH(<KOREAN_COL>)
PROMPT FETCH FIRST 20 ROWS ONLY;
PROMPT -- 소스/타겟 결과 일치 확인 (한글 깨짐 없음)

PROMPT
PROMPT =============================================
PROMPT [3-7] 참조 무결성 검증 (#24~25)
PROMPT =============================================

-- [검증항목 DV-024~025] 참조 무결성
PROMPT
PROMPT --- Orphan Row 확인 (FK 참조 부모 없는 자식 레코드) ---
PROMPT [타겟] FK DISABLED 상태로 Import 시 무결성 오류 데이터 존재 가능
PROMPT 아래 템플릿을 FK 관계 테이블별로 수정하여 실행
PROMPT
PROMPT 예시:
PROMPT SELECT COUNT(*) AS ORPHAN_CNT
PROMPT FROM <CHILD_SCHEMA>.<CHILD_TABLE> C
PROMPT WHERE NOT EXISTS (
PROMPT     SELECT 1 FROM <PARENT_SCHEMA>.<PARENT_TABLE> P
PROMPT     WHERE P.<PK_COL> = C.<FK_COL>
PROMPT );
PROMPT -- 기대값: 0건

PROMPT
PROMPT --- 현재 DISABLED FK 목록 확인 (Cut-over 후 ENABLE 예정 목록) ---
PROMPT [타겟] 실행
SELECT OWNER, TABLE_NAME, CONSTRAINT_NAME, STATUS
FROM DBA_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R' AND STATUS = 'DISABLED'
AND OWNER NOT IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS')
ORDER BY OWNER, TABLE_NAME;

PROMPT
PROMPT =============================================
PROMPT STEP 03 데이터 정합성 검증 완료
PROMPT =============================================

SPOOL OFF
EXIT
