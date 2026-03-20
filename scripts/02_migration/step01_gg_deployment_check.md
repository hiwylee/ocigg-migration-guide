# STEP 01. OCI GG Deployment 확인
# 실행 환경: [OCI콘솔] / [로컬]

> **목적**: OCI GG Deployment가 정상 기동 중이며, Oracle SE 19c를 지원하는 버전인지 확인
> **담당**: OCI GG 담당자
> **예상 소요**: 20분

---

## 1-1. Deployment 상태 및 버전 확인

- [ ] OCI콘솔 접속: Oracle Database → GoldenGate → Deployments
- [ ] Deployment 상태: **Active** 확인
- [ ] GoldenGate 버전 확인 (Oracle 19c SE 지원 여부 릴리즈 노트 대조)
- [ ] 자동 업데이트(Auto Upgrade) 정책 확인

### 자동 업데이트 비활성화 확인

```
[OCI콘솔] GoldenGate Deployment → Maintenance → Auto Upgrade: Disabled
※ 복제 중 자동 업그레이드 발생 시 Extract/Replicat ABEND 가능 → 반드시 비활성화
```

- [ ] Auto Upgrade: **Disabled** 확인

## 1-2. Admin Server 로그인 테스트

```bash
# [로컬] OCI GG Admin Server URL 접속
# https://<GG_DEPLOYMENT_URL>/
# 사용자: oggadmin / Password: <설정값>
# env.sh 참조: GG_ADMIN_URL, GG_ADMIN_USER, GG_ADMIN_PASS
```

- [ ] Admin Server 로그인 성공 확인

## 1-3. 결과 기록

| 항목 | 확인 결과 | 판정 | 확인자 |
|------|-----------|------|--------|
| Deployment 상태 | | [ ] PASS / [ ] FAIL | |
| GG 버전 (Oracle 19c SE 지원) | | [ ] PASS / [ ] FAIL | |
| 자동 업데이트 비활성화 | | [ ] PASS / [ ] FAIL | |
| Admin Server 로그인 | | [ ] PASS / [ ] FAIL | |

> **STEP 01 완료 서명**: __________________ 일시: __________________
