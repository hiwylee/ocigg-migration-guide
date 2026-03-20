# Phase 6-8 완료 체크리스트

> **프로젝트**: AWS RDS (Oracle SE) -> OCI DBCS (Oracle SE) 온라인 마이그레이션
> **적용 범위**: Phase 6 (검증) + Phase 7 (Cut-over) + Phase 8 (안정화)
> **참조 스크립트**: `scripts/03_validation/step01 ~ step12`

---

## Phase 6: 검증 (Validation)

### STEP 01. GG 프로세스 검증 (01_GG_Process -- 28항목)

- [ ] Pre-Check 항목 (#1~9) 전체 PASS
  - [ ] [GG-001] ENABLE_GOLDENGATE_REPLICATION = TRUE
  - [ ] [GG-002] Archive Log 모드 = ARCHIVELOG
  - [ ] [GG-003] Supplemental Logging (MIN) = YES
  - [ ] [GG-004] PK 없는 테이블 ALL COLUMNS 로깅 완료
  - [ ] [GG-005] Redo Log 최소 3그룹, 500MB 이상
  - [ ] [GG-006] GGADMIN 계정 권한 확인
  - [ ] [GG-007] RDS Redo Log 보존 48시간 이상
  - [ ] [GG-008] GG Deployment 버전 확인
  - [ ] [GG-009] 네트워크 연결 테스트 PASS
- [ ] Extract 상태 (#10~14) 전체 PASS
  - [ ] [GG-010] Extract RUNNING
  - [ ] [GG-011] Extract LAG < 30초
  - [ ] [GG-012] Checkpoint SCN 지속 증가
  - [ ] [GG-013] Extract Report ABEND/ERROR 없음
  - [ ] [GG-014] Extract Statistics 정상
- [ ] Pump 상태 (#15~17) 전체 PASS
  - [ ] [GG-015] Pump RUNNING
  - [ ] [GG-016] Pump LAG < 30초
  - [ ] [GG-017] Trail 정상 전송
- [ ] Replicat 상태 (#18~23) 전체 PASS
  - [ ] [GG-018] Replicat RUNNING
  - [ ] [GG-019] Replicat LAG < 30초
  - [ ] [GG-020] Replicat Statistics 정상
  - [ ] [GG-021] Replicat Report ABEND/ERROR 없음
  - [ ] [GG-022] Discard 레코드 0건
  - [ ] [GG-023] SUPPRESSTRIGGERS 적용 확인
- [ ] Trail File (#24~25) 전체 PASS
- [ ] 상시운영 (#26~28) 전체 PASS
- [ ] **STEP 01 완료 서명**: __________________ 일시: __________________

### STEP 02. 정적 구조 검증 (02_Static_Schema -- 38항목)

- [ ] 테이블/컬럼 구조 비교 (#1~5) PASS (MINUS 0건)
- [ ] 인덱스 완전성 (#6~9) PASS
  - [ ] 인덱스 목록 MINUS 0건
  - [ ] UNUSABLE 인덱스 0건
  - [ ] 인덱스 통계 존재
- [ ] 제약조건 (#10~15) PASS
  - [ ] PK/UK/FK/CHECK MINUS 0건
  - [ ] FK 외 DISABLED 0건
- [ ] 시퀀스/Synonym (#19~23) PASS
  - [ ] 시퀀스 속성 일치
  - [ ] Dangling Synonym 0건
- [ ] 사용자/권한 (#29~32) PASS
- [ ] INVALID 객체 (#37~38) 0건
- [ ] **STEP 02 완료 서명**: __________________ 일시: __________________

### STEP 03. 데이터 정합성 검증 (03_Data_Validation -- 25항목)

- [ ] Row Count 비교 (#1~3) PASS (1% 이내 차이)
- [ ] Checksum 비교 (#4~6) PASS
- [ ] 샘플 데이터 비교 (#7~9) PASS
- [ ] LOB 검증 (#10~14) PASS
- [ ] 데이터 타입 특이사항 (#15~20) PASS
- [ ] NLS 검증 (#21~23) PASS
- [ ] 참조 무결성 (#24~25) PASS (Orphan Row 0건)
- [ ] **STEP 03 완료 서명**: __________________ 일시: __________________

### STEP 04. 특수 객체 검증 (04_Special_Objects -- 42항목)

- [ ] MV (#1~8) PASS
  - [ ] MV 목록 MINUS 0건
  - [ ] MV REFRESH 동작 성공
- [ ] Trigger (#9~15) PASS
  - [ ] Trigger 목록 MINUS 0건
  - [ ] 복제 중 모두 DISABLED 상태
- [ ] DB Link (#16~22) PASS
  - [ ] DB Link 연결 테스트 성공
- [ ] DBMS_JOB/SCHEDULER (#23~29) PASS
  - [ ] 소스 JOB 모두 BROKEN
  - [ ] 타겟 SCHEDULER JOB 매핑 완료
- [ ] Sequence (#30~33) PASS (타겟 > 소스 + CACHE)
- [ ] 파티션 테이블 (#34~38) PASS
- [ ] DDL Replication (#39~42) 확인 완료
- [ ] **STEP 04 완료 서명**: __________________ 일시: __________________

### STEP 05. 통계정보 검증

- [ ] 통계 없는 테이블 0건
- [ ] 통계 없는 인덱스 0건
- [ ] 히스토그램 보유 컬럼 소스/타겟 일치
- [ ] 7일 초과 경과 통계 재수집 완료
- [ ] **STEP 05 완료 서명**: __________________ 일시: __________________

### STEP 06. 주의사항 체크 (05_Migration_Caution -- 26항목)

- [ ] SE 제약 항목 (#1~6) 전체 확인 완료
- [ ] OCI GG 항목 (#7~13) 전체 확인 완료
- [ ] Cut-over 준비 항목 (#14~19) 전체 확인 완료
- [ ] 상시운영 항목 (#20~26) 전체 확인 완료
- [ ] **STEP 06 완료 서명**: __________________ 일시: __________________

### STEP 07. Cut-over 직전 최종 확인

- [ ] INVALID 객체 0건
- [ ] UNUSABLE 인덱스 0건
- [ ] 오브젝트 유형별 COUNT 소스/타겟 일치
- [ ] 통계 없는 테이블/인덱스 0건
- [ ] Sequence GAP 정상
- [ ] **STEP 07 완료 서명**: __________________ 일시: __________________

### STEP 08. Go/No-Go 판정

- [ ] 전체 검증 결과 집계 완료
- [ ] 중요도 [상] 항목 전체 PASS 확인
- [ ] WARN 항목 원인 분석 및 조치 계획 완료
- [ ] **최종 판정**: Go / Conditional Go / No-Go
- [ ] 전 담당자 서명 완료
- [ ] **STEP 08 완료 서명**: __________________ 일시: __________________

---

## Phase 7: Cut-over

### STEP 09. Cut-over 사전 체크리스트

- [ ] GG LAG < 5초 확인
- [ ] Cut-over 준비 스크립트 전체 준비 완료
- [ ] 팀 준비 상태 전원 확인 완료
- [ ] 유지보수 공지 완료
- [ ] **STEP 09 완료 서명**: __________________ 일시: __________________

### STEP 10. Cut-over 실행

- [ ] Step 1: 소스 DB 애플리케이션 세션 차단 완료
- [ ] Step 2: 소스 DBMS_JOB BROKEN 처리 완료
- [ ] Step 3: 소스 CURRENT_SCN 기록 완료
  - SCN: __________________ | 시각: __________________
- [ ] Step 4: GG LAG = 0 확인 완료
- [ ] Step 5~6: Replicat 중지 + HANDLECOLLISIONS 제거 확인
- [ ] Step 7: 타겟 DB 최종 데이터 검증 완료
- [ ] Step 8a: Trigger 재활성화 완료
- [ ] Step 8b: FK Constraint 재활성화 완료
- [ ] Step 8c: GG 프로세스 완전 중지 + Sequence 재설정 완료
- [ ] Step 8d: DBMS_SCHEDULER JOB 활성화 완료
- [ ] Step 8e: DB Link 연결 테스트 PASS
- [ ] Step 9: 애플리케이션 연결 전환 (DNS/연결문자열) 완료
- [ ] Step 10: Smoke Test PASS
- [ ] **Cut-over 완료 시각**: __________________
- [ ] **총 소요 시간**: ______ 분
- [ ] **STEP 10 완료 서명**: __________________ 일시: __________________

### STEP 11. Cut-over 후 즉시 검증

- [ ] 데이터 최신성 확인 PASS
- [ ] DISABLED Trigger 0건
- [ ] DISABLED FK 0건
- [ ] Sequence 현재값 정상
- [ ] DISABLED SCHEDULER JOB 0건
- [ ] INVALID 객체 0건
- [ ] UNUSABLE 인덱스 0건
- [ ] 통계 없는 테이블 0건
- [ ] Smoke Test PASS
- [ ] 에러 로그 (30분 모니터링) 이상 없음
- [ ] 전 담당자 서명 완료
- [ ] **STEP 11 완료 서명**: __________________ 일시: __________________

---

## Phase 8: 안정화

### STEP 12. Cut-over 후 안정화 모니터링

- [ ] D+1 일일 모니터링 완료
- [ ] D+2 일일 모니터링 완료
- [ ] D+3 일일 모니터링 완료
- [ ] D+7 주간 모니터링 완료
  - [ ] Sequence GAP 확인
  - [ ] Constraint DISABLED 상태 점검
  - [ ] 소스 RDS Read-Only 전환 검토
- [ ] D+14 최종 모니터링 완료
  - [ ] 소스 RDS 종료 결정
  - [ ] OCI GG Deployment 종료/유지 결정
- [ ] Discard 파일 일일 점검 0건 유지
- [ ] 롤백 트리거 조건 발생 없음 확인
- [ ] **STEP 12 완료 서명**: __________________ 일시: __________________

---

## 최종 마이그레이션 완료 서명

| 역할 | 성명 | 서명 | 일시 |
|------|------|------|------|
| 마이그레이션 리더 | | | |
| 소스 DBA (AWS) | | | |
| 타겟 DBA (OCI) | | | |
| OCI GG 담당자 | | | |
| 애플리케이션 담당 | | | |
| 비즈니스 담당 | | | |
