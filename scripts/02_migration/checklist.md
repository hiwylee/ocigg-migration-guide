# Phase 3-5 완료 체크리스트

> **프로젝트**: AWS RDS (Oracle SE) → OCI DBCS (Oracle SE) 온라인 마이그레이션
> **적용 범위**: Phase 3 (OCI GG 구성) + Phase 4 (초기 데이터 적재) + Phase 5 (델타 동기화)
> **실행 환경**: [소스] / [타겟] / [GG]

---

## Phase 3 완료 체크리스트 — OCI GoldenGate 구성

| # | 항목 | 기대값 | 확인 결과 | 판정 | 확인자 |
|---|------|--------|-----------|------|--------|
| 1 | OCI GG Deployment 정상 동작 | Active | | [ ] PASS / [ ] FAIL | |
| 2 | GG 버전 (Oracle 19c SE 지원) | 지원 버전 | | [ ] PASS / [ ] FAIL | |
| 3 | 자동 업데이트 비활성화 | Disabled | | [ ] PASS / [ ] FAIL | |
| 4 | Admin Server 로그인 | 성공 | | [ ] PASS / [ ] FAIL | |
| 5 | Credential Store 등록 (소스/타겟) | 2건 | | [ ] PASS / [ ] FAIL | |
| 6 | 소스 Connection 연결 테스트 | PASS | | [ ] PASS / [ ] FAIL | |
| 7 | 타겟 Connection 연결 테스트 | PASS | | [ ] PASS / [ ] FAIL | |
| 8 | Heartbeat Table 소스/타겟 생성 | 각 1건 이상 | | [ ] PASS / [ ] FAIL | |
| 9 | Extract EXT1 등록 (STOPPED) | STOPPED | | [ ] PASS / [ ] FAIL | |
| 10 | Pump PUMP1 등록 (STOPPED) | STOPPED | | [ ] PASS / [ ] FAIL | |
| 11 | Replicat REP1 등록 (STOPPED) | STOPPED | | [ ] PASS / [ ] FAIL | |
| 12 | Trail File 저장소 (Object Storage) 연결 | PASS | | [ ] PASS / [ ] FAIL | |

### Phase 3 완료 승인

| 역할 | 성명 | 서명 | 일시 |
|------|------|------|------|
| 마이그레이션 리더 | | | |
| OCI GG 담당자 | | | |

> **Phase 3 → Phase 4 전환 조건**: 위 체크리스트 전 항목 PASS 완료

---

## Phase 4 완료 체크리스트 — 초기 데이터 적재

| # | 항목 | 기대값 | 확인 결과 | 판정 | 확인자 |
|---|------|--------|-----------|------|--------|
| 1 | UNDO_RETENTION >= 예상 Export 시간 + 여유분 | 충분 | | [ ] PASS / [ ] FAIL | |
| 2 | UNDO 테이블스페이스 여유 공간 충분 | DB 크기의 10% 이상 | | [ ] PASS / [ ] FAIL | |
| 3 | MIGRATION_USER Flashback 권한 확인 | 2건 | | [ ] PASS / [ ] FAIL | |
| 4 | Export SCN 기록 완료 | SCN 값 기록됨 | | [ ] PASS / [ ] FAIL | |
| 5 | Extract SCN 기준점 재등록 완료 | SCN 일치 | | [ ] PASS / [ ] FAIL | |
| 6 | expdp Export 오류 0건 | 0건 | | [ ] PASS / [ ] FAIL | |
| 7 | expdp "successfully completed" 메시지 | 확인 | | [ ] PASS / [ ] FAIL | |
| 8 | OCI Object Storage 업로드 완료 | 완료 | | [ ] PASS / [ ] FAIL | |
| 9 | 파일 개수 소스/타겟 일치 | 일치 | | [ ] PASS / [ ] FAIL | |
| 10 | 타겟 DBCS 다운로드 완료 | 완료 | | [ ] PASS / [ ] FAIL | |
| 11 | FK DISABLE 완료 | 전체 FK DISABLED | | [ ] PASS / [ ] FAIL | |
| 12 | Trigger DISABLE 완료 | 전체 Trigger DISABLED | | [ ] PASS / [ ] FAIL | |
| 13 | impdp Import 오류 0건 (허용 가능 오류 제외) | 0건 | | [ ] PASS / [ ] FAIL | |
| 14 | impdp "successfully completed" 메시지 | 확인 | | [ ] PASS / [ ] FAIL | |
| 15 | 통계정보 Import 완료 (NO_STATS = 0) | 0건 | | [ ] PASS / [ ] FAIL | |
| 16 | INVALID 객체 0건 (재컴파일 후) | 0건 | | [ ] PASS / [ ] FAIL | |
| 17 | UNUSABLE 인덱스 0건 (재빌드 후) | 0건 | | [ ] PASS / [ ] FAIL | |
| 18 | Row Count 소스/타겟 일치 (핵심 테이블) | 0% 오차 | | [ ] PASS / [ ] FAIL | |

### Phase 4 완료 승인

| 역할 | 성명 | 서명 | 일시 |
|------|------|------|------|
| 마이그레이션 리더 | | | |
| 소스 DBA | | | |
| 타겟 DBA | | | |

> **Phase 4 → Phase 5 전환 조건**: 위 체크리스트 전 항목 PASS 완료

---

## Phase 5 완료 체크리스트 — 델타 동기화

| # | 항목 | 기대값 | 확인 결과 | 판정 | 확인자 |
|---|------|--------|-----------|------|--------|
| 1 | EXT1 상태 RUNNING (24h+) | RUNNING | | [ ] PASS / [ ] FAIL | |
| 2 | EXT1 LAG < 30초 (24h+) | < 30s | | [ ] PASS / [ ] FAIL | |
| 3 | PUMP1 상태 RUNNING (24h+) | RUNNING | | [ ] PASS / [ ] FAIL | |
| 4 | PUMP1 LAG < 30초 (24h+) | < 30s | | [ ] PASS / [ ] FAIL | |
| 5 | REP1 상태 RUNNING (24h+) | RUNNING | | [ ] PASS / [ ] FAIL | |
| 6 | REP1 LAG < 30초 (24h+) | < 30s | | [ ] PASS / [ ] FAIL | |
| 7 | Discard 파일 레코드 0건 (누적) | 0건 | | [ ] PASS / [ ] FAIL | |
| 8 | ABEND 이력 없음 | 0건 | | [ ] PASS / [ ] FAIL | |
| 9 | Trail File 용량 안정적 (급증 없음) | 정상 | | [ ] PASS / [ ] FAIL | |
| 10 | Heartbeat Table 정상 업데이트 | 정상 | | [ ] PASS / [ ] FAIL | |
| 11 | HANDLECOLLISIONS 제거 완료 | 제거됨 | | [ ] PASS / [ ] FAIL | |

### Phase 5 완료 승인

| 역할 | 성명 | 서명 | 일시 |
|------|------|------|------|
| 마이그레이션 리더 | | | |
| OCI GG 담당자 | | | |
| 타겟 DBA | | | |

> **Phase 5 → Phase 6 전환 조건**: 위 체크리스트 전 항목 PASS 완료
> **다음 단계**: `03.validation.md` 검증 단계 진행
