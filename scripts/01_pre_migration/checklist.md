# Phase 0-2 사전 작업 완료 체크리스트

> **실행 환경**: [로컬] / [소스] / [타겟]
> 아래 모든 항목이 완료되어야 Phase 3 (OCI GG 구성) 진행 가능

---

## Phase 0 -- 사전 준비

| STEP | 항목 | 스크립트 | 판정 | 완료 시각 | 담당자 |
|------|------|---------|------|---------|--------|
| 01 | 소스 DB 인벤토리 수집 완료 | step01_inventory.sql | | | |
| 02 | 마이그레이션 대상 스키마 확정 및 서명 완료 | step02_schema_list.sql | | | |
| 03 | OCI DBCS / GG / Object Storage 생성 완료 | step03_oci_infra_checklist.md | | | |
| 04 | 네트워크 연결 및 테스트 완료 | step04_network_test.sh | | | |
| 05 | GGADMIN / MIGRATION_USER 계정 생성 완료 (소스/타겟) | step05_create_accounts.sql | | | |
| 06 | NLS / Timezone 소스/타겟 일치 확인 완료 | step06_nls_check.sql | | | |

### Phase 0 세부 체크

- [ ] STEP 01: 인벤토리 수집 완료, 결과 스프레드시트에 기록
- [ ] STEP 01: BITMAP Index 존재 시 대체 방안 별도 수립
- [ ] STEP 01: XMLTYPE 테이블 존재 시 GG 복제 제외 여부 확인
- [ ] STEP 02: 이전 대상 스키마 목록 확정 및 관계자 서명
- [ ] STEP 03: DBCS 기동 상태 AVAILABLE 확인
- [ ] STEP 03: GG Deployment 상태 ACTIVE 확인
- [ ] STEP 03: Object Storage 버킷 생성 및 권한 설정
- [ ] STEP 04: 모든 구간 네트워크 연결 테스트 통과
- [ ] STEP 05: GGADMIN 소스/타겟 생성 및 권한 확인
- [ ] STEP 05: MIGRATION_USER 소스/타겟 생성 및 접속 테스트
- [ ] STEP 06: NLS_CHARACTERSET 소스/타겟 일치
- [ ] STEP 06: DBTIMEZONE 소스/타겟 일치

---

## Phase 1 -- 소스 DB 준비

| STEP | 항목 | 스크립트 | 판정 | 완료 시각 | 담당자 |
|------|------|---------|------|---------|--------|
| 07 | ENABLE_GOLDENGATE_REPLICATION = TRUE | step07_enable_gg.sql | | | |
| 08 | LOG_MODE = ARCHIVELOG | step08_archivelog_check.sql | | | |
| 09 | Archivelog 보존 기간 >= 24h | step09_redo_retention.sql | | | |
| 10 | Redo Log 그룹 >= 3, 크기 >= 500MB | step10_redo_log_check.sql | | | |
| 11 | streams_pool_size >= 256MB | step11_streams_pool.sql | | | |
| 12 | SUPPLEMENTAL_LOG_DATA_MIN = YES | step12_supplemental_log.sql | | | |
| 13 | PK 없는 테이블 ALL COLUMNS 로깅 적용 완료 | step13_nopk_suplog.sql | | | |
| 14 | 파티션 테이블 Supplemental Log 확인 완료 | step14_partition_suplog.sql | | | |

### Phase 1 세부 체크

- [ ] STEP 07: enable_goldengate_replication = TRUE 확인
- [ ] STEP 08: LOG_MODE = ARCHIVELOG 확인
- [ ] STEP 09: archivelog retention hours >= 24 (권장 48)
- [ ] STEP 10: Redo Log 그룹 수/크기 적합성 확인
- [ ] STEP 11: streams_pool_size >= 256MB (AWS 콘솔에서 설정 후 재기동)
- [ ] STEP 12: SUPPLEMENTAL_LOG_DATA_MIN = YES 확인
- [ ] STEP 13: PK 없는 테이블 ALL COLUMNS 로깅 적용 완료 (NO_PK_TABLES = SUPLOG_APPLIED)
- [ ] STEP 14: 파티션 테이블 SUPLOG_STATUS = 'MISSING' 건수 = 0

---

## Phase 2 -- 타겟 DB 준비

| STEP | 항목 | 스크립트 | 판정 | 완료 시각 | 담당자 |
|------|------|---------|------|---------|--------|
| 15 | 타겟 NLS 파라미터 소스와 일치 | step15_target_nls.sql | | | |
| 16 | METADATA_ONLY expdp 완료 및 전송 완료 | step16_metadata_export.sh | | | |
| 17 | METADATA_ONLY impdp 완료 (치명적 오류 0건) | step17_metadata_import.sh | | | |
| 18 | 오브젝트 완전성 전수 비교 -- COUNT 일치 | step18_object_compare.sql | | | |
| 19 | INVALID 객체 재컴파일 완료 (INVALID = 0건) | step19_recompile_invalid.sql | | | |
| 20 | UNUSABLE 인덱스 0건 확인 (REBUILD 완료) | step20_index_valid.sql | | | |
| 21 | Directory / External Table 처리 완료 | step21_directory_extable.sql | | | |
| 22 | 특수 객체(MV/DB Link/JOB) 처리 준비 완료 | step22_special_objects.sql | | | |
| 23 | DISABLE/ENABLE 스크립트 생성 및 검증 완료 | step23_disable_scripts.sql | | | |
| 24 | 통계정보 Export 완료 (또는 옵션 B 선택 확정) | step24_stats_export.sh | | | |

### Phase 2 세부 체크

- [ ] STEP 15: NLS_CHARACTERSET, NLS_DATE_FORMAT, DBTIMEZONE 소스와 일치
- [ ] STEP 16: expdp "completed successfully" 확인, ORA- 에러 0건
- [ ] STEP 16: 덤프 파일 OCI Object Storage 업로드 완료
- [ ] STEP 17: impdp "completed" 확인, 치명적 ORA- 에러 0건
- [ ] STEP 18: OBJECT_TYPE별 COUNT 소스/타겟 일치
- [ ] STEP 18: 인덱스 상세(FBI, 파티션) 일치
- [ ] STEP 18: 제약조건 수 일치
- [ ] STEP 18: 시퀀스 속성 일치
- [ ] STEP 18: 사용자/Profile 일치
- [ ] STEP 19: INVALID 객체 수 = 0
- [ ] STEP 20: UNUSABLE 인덱스 수 = 0
- [ ] STEP 21: Directory Object OCI 경로로 재생성 완료
- [ ] STEP 21: External Table 처리 완료 (해당 시)
- [ ] STEP 22: MV 목록 및 REFRESH 방식 파악 완료
- [ ] STEP 22: DB Link OCI 환경 기준 재생성 및 연결 테스트 완료
- [ ] STEP 22: DBMS_JOB -> DBMS_SCHEDULER 전환 스크립트 준비 (DISABLED 상태)
- [ ] STEP 23: disable_triggers.sql / enable_triggers.sql 생성 완료
- [ ] STEP 23: disable_fk.sql / enable_fk.sql 생성 완료
- [ ] STEP 24: 통계 Export 완료 또는 옵션 B 선택 확정

---

## 최종 승인 (사전 작업 완료)

> 아래 서명 완료 후 Phase 3 OCI GoldenGate 구성 진행

| 역할 | 성명 | 서명 | 날짜/시각 |
|------|------|------|---------|
| 소스 DBA (AWS) | | | |
| 타겟 DBA (OCI) | | | |
| OCI GG 담당자 | | | |
| 마이그레이션 리더 | | | |
