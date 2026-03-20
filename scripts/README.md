# 마이그레이션 실행 스크립트 가이드

> **프로젝트**: AWS RDS (Oracle SE) → OCI DBCS (Oracle SE) 온라인 마이그레이션
> **스크립트 기준 문서**: `plan/01.pre_migration.md`, `plan/02_migration.md`, `plan/03.validation.md`

---

## 사전 준비

### 1. 환경변수 설정

모든 스크립트는 `config/env.sh`를 참조합니다. 실행 전 반드시 환경변수를 설정하세요:

```bash
vi scripts/config/env.sh
```

설정이 필요한 주요 변수:

| 변수 | 설명 | 예시 |
|------|------|------|
| `SRC_DB_HOST` | 소스 RDS 엔드포인트 | `mydb.xxxx.ap-northeast-2.rds.amazonaws.com` |
| `SRC_DB_SID` | 소스 DB SID | `ORCL` |
| `TGT_DB_HOST` | 타겟 DBCS 호스트 | `dbcs-node1.subnet.vcn.oraclevcn.com` |
| `TGT_DB_SID` | 타겟 DB SID | `ORCL` |
| `MIGRATION_SCHEMAS` | 대상 스키마 (쉼표 구분) | `SCHEMA1,SCHEMA2` |
| `SRC_DBA_PASS` / `TGT_DBA_PASS` | DB 관리자 비밀번호 | — |
| `GG_ADMIN_URL` | GoldenGate Admin Server URL | `https://gg-admin:443` |

### 2. 실행 권한 부여

```bash
chmod +x scripts/01_pre_migration/*.sh
chmod +x scripts/02_migration/*.sh
chmod +x scripts/03_validation/*.sh
```

### 3. 로그 디렉토리

모든 스크립트 실행 결과는 `scripts/logs/` 디렉토리에 자동 저장됩니다.

---

## 실행 순서

### Phase 0-2: 사전 마이그레이션 (`01_pre_migration/`)

| 순서 | 스크립트 | 실행 환경 | 설명 |
|------|----------|-----------|------|
| 1 | `step01_inventory.sql` | 소스 | DB 인벤토리 수집 |
| 2 | `step02_schema_list.sql` | 소스 | 대상 스키마 확정 |
| 3 | `step03_oci_infra_checklist.md` | OCI콘솔 | OCI 인프라 생성 (체크리스트) |
| 4 | `step04_network_test.sh` | 로컬 | 네트워크 연결 테스트 |
| 5 | `step05_create_accounts.sql` | 소스+타겟 | GGADMIN, MIGRATION_USER 생성 |
| 6 | `step06_nls_check.sql` | 소스+타겟 | NLS/Timezone 비교 |
| 7 | `step07_enable_gg.sql` | 소스 | GG 활성화 파라미터 |
| 8 | `step08_archivelog_check.sql` | 소스 | Archive Log 모드 확인 |
| 9 | `step09_redo_retention.sql` | 소스 | Redo Log 보존 기간 설정 |
| 10 | `step10_redo_log_check.sql` | 소스 | Redo Log 그룹/크기 확인 |
| 11 | `step11_streams_pool.sql` | 소스 | Streams Pool 메모리 설정 |
| 12 | `step12_supplemental_log.sql` | 소스 | Supplemental Logging 활성화 |
| 13 | `step13_nopk_suplog.sql` | 소스 | PK 없는 테이블 ALL COLUMNS 로깅 |
| 14 | `step14_partition_suplog.sql` | 소스 | 파티션 테이블 Supplemental Log |
| 15 | `step15_target_nls.sql` | 타겟 | 타겟 NLS 파라미터 설정 |
| 16 | `step16_metadata_export.sh` | 소스 | METADATA_ONLY expdp |
| 17 | `step17_metadata_import.sh` | 타겟 | METADATA_ONLY impdp |
| 18 | `step18_object_compare.sql` | 소스+타겟 | 오브젝트 완전성 전수 비교 |
| 19 | `step19_recompile_invalid.sql` | 타겟 | INVALID 객체 재컴파일 |
| 20 | `step20_index_valid.sql` | 타겟 | 인덱스 VALID 상태 확인 |
| 21 | `step21_directory_extable.sql` | 타겟 | Directory/External Table 처리 |
| 22 | `step22_special_objects.sql` | 타겟 | 특수 객체 처리 |
| 23 | `step23_disable_scripts.sql` | 타겟 | FK/Trigger DISABLE 스크립트 생성 |
| 24 | `step24_stats_export.sh` | 소스 | 통계정보 Export |
| ✓ | `checklist.md` | — | Phase 0-2 완료 체크리스트 |

### Phase 3-5: 마이그레이션 (`02_migration/`)

| 순서 | 스크립트 | 실행 환경 | 설명 |
|------|----------|-----------|------|
| 1 | `step01_gg_deployment_check.md` | OCI콘솔 | GG Deployment 확인 (체크리스트) |
| 2 | `step02_connection_setup.sh` | GG | 소스/타겟 Connection 생성 |
| 3 | `step03_heartbeat.sql` | 소스+타겟 | Heartbeat Table 추가 |
| 4 | `step04_extract_setup.sh` | GG | Extract(EXT1) 설정 |
| 5 | `step05_pump_setup.sh` | GG | Data Pump(PUMP1) 설정 |
| 6 | `step06_replicat_setup.sh` | GG | Replicat(REP1) 설정 |
| 7 | `step07_undo_check.sql` | 소스 | UNDO/Flashback 사전 확인 |
| 8 | `step08_export_scn.sql` | 소스 | expdp SCN 고정 |
| 9 | `step09_extract_scn_reregister.sh` | GG | Extract SCN 재등록 |
| 10 | `step10_data_export.sh` | 소스 | DATA_ONLY expdp |
| 11 | `step11_dump_transfer.sh` | 로컬 | Dump → OCI Object Storage 전송 |
| 12 | `step12_disable_and_import.sh` | 타겟 | FK/Trigger DISABLE + impdp |
| 13 | `step13_stats_import.sh` | 타겟 | 통계정보 Import |
| 14 | `step14_post_import_check.sql` | 타겟 | Import 후 오브젝트 확인 |
| 15 | `step15_initial_rowcount.sql` | 소스+타겟 | 초기 Row Count 비교 |
| 16 | `step16_start_replication.sh` | GG | GG 복제 시작 (ATCSN) |
| 17 | `step17_gg_status_check.sh` | GG | GG 프로세스 상태 확인 |
| 18 | `step18_lag_monitoring.sh` | GG | LAG 안정화 모니터링 (24h+) |
| ✓ | `checklist.md` | — | Phase 3-5 완료 체크리스트 |

### Phase 6-8: 검증 및 Cut-over (`03_validation/`)

| 순서 | 스크립트 | 실행 환경 | 설명 |
|------|----------|-----------|------|
| 1 | `step01_gg_process_check.sql` | 소스+타겟 | GG 프로세스 검증 (SQL) |
| 1 | `step01_gg_process_check.sh` | GG | GG GGSCI 명령 검증 |
| 2 | `step02_static_schema.sql` | 소스+타겟 | 정적 구조 검증 (38항목) |
| 3 | `step03_data_validation.sql` | 소스+타겟 | 데이터 정합성 검증 (25항목) |
| 4 | `step04_special_objects.sql` | 소스+타겟 | 특수 객체 검증 (42항목) |
| 5 | `step05_stats_validation.sql` | 타겟 | 통계정보 검증 |
| 6 | `step06_caution_checklist.md` | — | 주의사항 체크 (26항목) |
| 7 | `step07_final_check.sql` | 소스+타겟 | Cut-over 직전 최종 확인 |
| 8 | `step08_go_nogo.md` | — | Go/No-Go 판정 템플릿 |
| 9 | `step09_cutover_precheck.sql` | 소스+타겟 | Cut-over 사전 체크 |
| 10 | `step10_cutover_execute.sh` | GG+타겟 | Cut-over 실행 |
| 11 | `step11_cutover_verify.sql` | 타겟 | Cut-over 후 즉시 검증 |
| 12 | `step12_stabilization.sh` | 타겟+GG | 안정화 모니터링 |
| ✓ | `checklist.md` | — | Phase 6-8 완료 체크리스트 |

---

## SQL 스크립트 실행 방법

```bash
# 소스 DB 접속 실행
sqlplus -S ${SRC_DBA_USER}/${SRC_DBA_PASS}@"${SRC_TNS}" @scripts/01_pre_migration/step01_inventory.sql

# 타겟 DB 접속 실행
sqlplus -S ${TGT_DBA_USER}/${TGT_DBA_PASS}@"${TGT_TNS}" AS SYSDBA @scripts/01_pre_migration/step15_target_nls.sql
```

## Shell 스크립트 실행 방법

```bash
# 직접 실행 (env.sh 자동 로드)
./scripts/01_pre_migration/step04_network_test.sh
```

---

## 주의사항

1. **비밀번호 관리**: `config/env.sh`에 비밀번호가 포함되어 있습니다. Git에 커밋하지 마세요.
2. **실행 순서**: 각 Phase 내 STEP은 순서대로 실행해야 합니다. Phase 간 전환 시 체크리스트를 반드시 확인하세요.
3. **롤백**: Phase 4 이전까지는 롤백이 비교적 쉽습니다. Phase 4 이후에는 `plan/migration_plan.md`의 롤백 절차를 참조하세요.
4. **로그 보관**: `scripts/logs/` 디렉토리의 실행 로그는 마이그레이션 완료 후 최소 2주간 보관하세요.
