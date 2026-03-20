# STEP 03. OCI 인프라 생성 체크리스트

> **실행 환경**: [OCI콘솔]
> **목적**: 타겟 OCI 환경(DBCS, GoldenGate, Object Storage) 구성
> **담당**: OCI 인프라 담당 + OCI DBA

---

## 3-1. OCI DBCS 인스턴스 생성

`[OCI콘솔]` OCI → Oracle Database → Oracle Base Database Service

| 설정 항목 | 소스(RDS) 값 | 타겟(DBCS) 설정값 | 확인 |
|----------|------------|----------------|------|
| Oracle 버전 | | ※ 소스와 동일 버전 | - [ ] |
| Edition | SE | SE | - [ ] |
| OCPU | | ≥ 소스 동등 | - [ ] |
| 메모리(GB) | | ≥ 소스 동등 | - [ ] |
| 스토리지(GB) | | ≥ 소스 실사용량 x 1.3 | - [ ] |
| 리전 | ap-northeast-1 | ap-tokyo-1 | - [ ] |
| NLS_CHARACTERSET | | 소스와 동일 (AL32UTF8) | - [ ] |

- [ ] DBCS 기동 상태 AVAILABLE 확인
- [ ] sqlplus SYS 접속 테스트 완료

> **DBCS Endpoint**: ________________________
> **Service Name**: ________________________

---

## 3-2. OCI GoldenGate Deployment 생성

`[OCI콘솔]` OCI → GoldenGate → Deployments → Create

| 설정 항목 | 설정값 | 확인 |
|----------|--------|------|
| Deployment 이름 | | - [ ] |
| License 유형 | BRING_YOUR_OWN_LICENSE | - [ ] |
| Database 유형 | Oracle Database | - [ ] |
| 버전 | Oracle 19c 지원 버전 확인 | - [ ] |
| OCPU | | - [ ] |
| 자동 업데이트 정책 | **비활성화** (복제 중 자동 패치 방지) | - [ ] |

```
-- GG Deployment 버전 확인 (OCI GG Admin Console)
-- Administration → About → Version
-- Oracle 19c SE 지원 버전인지 릴리즈 노트 대조
```

- [ ] Deployment 상태 ACTIVE 확인
- [ ] GG Admin Console 접근 가능 확인
- [ ] OCI GG Admin Server URL: ________________________

---

## 3-3. OCI Object Storage 버킷 생성

`[OCI콘솔]` OCI → Storage → Object Storage → Create Bucket

| 버킷명 | 용도 | 보존 정책 | 확인 |
|--------|------|----------|------|
| `gg-trail-bucket` | GG Trail File 저장 | 7일 이상 | - [ ] |
| `migration-dump-bucket` | expdp/impdp Dump File | 이전 완료 후 30일 | - [ ] |

- [ ] 버킷 접근 권한 설정 (OCI GG Deployment 접근 허용)
- [ ] PAR(Pre-Authenticated Request) 또는 IAM 정책 설정

---

> **완료 시각**: ____________ | **담당자 서명**: ____________
