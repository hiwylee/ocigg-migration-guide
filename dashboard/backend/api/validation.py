from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, timezone
import aiosqlite
import os

from core.db import get_db
from api.auth import get_current_user, UserInfo

router = APIRouter()

# ---------------------------------------------------------------------------
# Domain definitions
# ---------------------------------------------------------------------------

DOMAINS = [
    ("01_GG_Process",       28),
    ("02_Static_Schema",    38),
    ("03_Data_Validation",  25),
    ("04_Special_Objects",  42),
    ("05_Migration_Caution",26),
]

DOMAIN_ITEMS = {
    "01_GG_Process": [
        ("GoldenGate Extract 프로세스 기동 전 점검",        "HIGH"),
        ("Extract 파라미터 파일 검증",                     "HIGH"),
        ("Extract SCN 기준점 확인",                        "HIGH"),
        ("Supplemental Logging 활성화 확인 (MIN)",         "HIGH"),
        ("PK 없는 테이블 ALL COLUMNS Supplemental Logging","HIGH"),
        ("Streams Pool 크기 확인 (≥256MB)",                "HIGH"),
        ("ENABLE_GOLDENGATE_REPLICATION 파라미터 확인",    "HIGH"),
        ("Extract Trail 파일 생성 확인",                   "MEDIUM"),
        ("Extract 통계 초기 수집",                         "MEDIUM"),
        ("Data Pump 프로세스 기동 전 점검",                "HIGH"),
        ("Pump 파라미터 파일 검증",                        "HIGH"),
        ("Pump Trail 전송 확인",                           "HIGH"),
        ("네트워크 구간 지연 측정 (AWS→OCI)",              "MEDIUM"),
        ("Replicat 프로세스 기동 전 점검",                 "HIGH"),
        ("Replicat 파라미터 파일 검증",                    "HIGH"),
        ("Replicat 적용 모드 확인 (INTEGRATED/CLASSIC)",   "MEDIUM"),
        ("Replicat Checkpoint 위치 확인",                  "MEDIUM"),
        ("GG LAG 실시간 모니터링 기준값 설정",             "HIGH"),
        ("Extract LAG < 30초 확인",                        "HIGH"),
        ("Pump LAG < 30초 확인",                           "HIGH"),
        ("Replicat LAG < 30초 확인",                       "HIGH"),
        ("24시간 LAG 안정화 확인",                         "HIGH"),
        ("GoldenGate 에러 로그 점검",                      "MEDIUM"),
        ("Discard 파일 크기 확인",                         "MEDIUM"),
        ("GG 통계 (Inserts/Updates/Deletes) 정합성 확인",  "HIGH"),
        ("GG 관리 계정 권한 확인 (src/tgt)",               "MEDIUM"),
        ("GG Deployment 상태 확인",                        "HIGH"),
        ("GG 버전 호환성 확인",                            "MEDIUM"),
    ],
    "02_Static_Schema": [
        ("테이블 수 비교 (src vs tgt)",                    "HIGH"),
        ("컬럼 정의 비교 (데이터타입, NOT NULL)",          "HIGH"),
        ("PK 제약조건 비교",                               "HIGH"),
        ("UK 제약조건 비교",                               "HIGH"),
        ("FK 제약조건 비교",                               "HIGH"),
        ("CHECK 제약조건 비교",                            "MEDIUM"),
        ("인덱스 목록 비교 (개수, 이름)",                  "HIGH"),
        ("인덱스 컬럼 구성 비교",                          "HIGH"),
        ("BITMAP 인덱스 존재 여부 확인 (SE 미지원)",       "HIGH"),
        ("Function-Based 인덱스 비교",                     "MEDIUM"),
        ("시퀀스 목록 및 현재값 비교",                     "HIGH"),
        ("시퀀스 INCREMENT BY / NOCYCLE 설정 비교",        "MEDIUM"),
        ("뷰(VIEW) 목록 및 정의 비교",                     "MEDIUM"),
        ("뷰 컴파일 오류 확인",                            "HIGH"),
        ("동의어(SYNONYM) 비교",                           "MEDIUM"),
        ("공개 동의어(PUBLIC SYNONYM) 비교",               "LOW"),
        ("저장 프로시저 목록 비교",                        "HIGH"),
        ("함수(FUNCTION) 목록 비교",                       "HIGH"),
        ("패키지(PACKAGE) 목록 비교",                      "HIGH"),
        ("패키지 바디(PACKAGE BODY) 컴파일 상태 확인",     "HIGH"),
        ("타입(TYPE) 목록 비교",                           "MEDIUM"),
        ("트리거(TRIGGER) 활성화 상태 비교",               "HIGH"),
        ("INVALID 객체 수 확인 (tgt ≤ src)",               "HIGH"),
        ("INVALID 객체 상세 목록 분석",                    "HIGH"),
        ("테이블 스페이스 여유 공간 확인",                 "HIGH"),
        ("스키마별 세그먼트 크기 비교",                    "MEDIUM"),
        ("파티션 테이블 목록 비교",                        "HIGH"),
        ("파티션 타입 비교 (RANGE/LIST/HASH)",             "MEDIUM"),
        ("LOB 컬럼 스토리지 파라미터 비교",                "MEDIUM"),
        ("클러스터(CLUSTER) 객체 확인",                    "LOW"),
        ("데이터베이스 링크(DB LINK) 목록 비교",           "HIGH"),
        ("디렉터리(DIRECTORY) 객체 비교",                  "MEDIUM"),
        ("스키마 DDL 전체 Export 비교",                    "MEDIUM"),
        ("NLS 파라미터 비교 (src vs tgt)",                 "HIGH"),
        ("문자셋 확인 (AL32UTF8 등)",                      "HIGH"),
        ("권한(GRANT) 비교 (객체 권한)",                   "HIGH"),
        ("시스템 권한 비교",                               "MEDIUM"),
        ("롤(ROLE) 비교",                                  "MEDIUM"),
    ],
    "03_Data_Validation": [
        ("전체 테이블 행 수 비교",                         "HIGH"),
        ("도메인별 핵심 테이블 행 수 비교",                "HIGH"),
        ("샘플 체크섬 비교 (상위 N개 테이블)",             "HIGH"),
        ("LOB 데이터 크기 비교",                           "HIGH"),
        ("LOB 데이터 샘플 해시 비교",                      "HIGH"),
        ("날짜 컬럼 범위 비교 (MIN/MAX)",                  "MEDIUM"),
        ("숫자 컬럼 합계 비교 (SUM 샘플)",                 "MEDIUM"),
        ("NULL 비율 비교 (주요 컬럼)",                     "MEDIUM"),
        ("참조 무결성 확인 (FK 위반 행 수)",               "HIGH"),
        ("중복 PK 확인 (tgt)",                             "HIGH"),
        ("최신 삽입/수정 데이터 반영 확인 (Cutover 직전)", "HIGH"),
        ("NLS_DATE_FORMAT 변환 확인",                      "MEDIUM"),
        ("타임존 처리 확인 (TIMESTAMP WITH TZ)",           "HIGH"),
        ("CLOB 한글 데이터 무결성 확인",                   "HIGH"),
        ("BLOB 바이너리 데이터 무결성 확인",               "HIGH"),
        ("초기 적재(impdp) 완료 행 수 확인",               "HIGH"),
        ("델타 적용 후 행 수 재확인",                      "HIGH"),
        ("GG Replicat 적용 건수 vs Extract 발생 건수 비교","HIGH"),
        ("트랜잭션 일관성 확인 (COMMIT 단위)",             "HIGH"),
        ("대용량 테이블 청크 비교",                        "MEDIUM"),
        ("시퀀스 현재값 동기화 확인",                      "HIGH"),
        ("파티션별 행 수 비교",                            "MEDIUM"),
        ("삭제된 행 동기화 확인",                          "HIGH"),
        ("업데이트된 행 샘플 비교",                        "HIGH"),
        ("배치 처리 결과 데이터 비교",                     "MEDIUM"),
    ],
    "04_Special_Objects": [
        ("Materialized View 목록 비교",                    "HIGH"),
        ("MV 새로고침 모드 확인 (FAST/COMPLETE/FORCE)",    "HIGH"),
        ("MV 새로고침 그룹 확인",                          "MEDIUM"),
        ("MV Log 존재 여부 확인",                          "HIGH"),
        ("MV 데이터 행 수 비교",                           "HIGH"),
        ("MV 컴파일 오류 확인",                            "HIGH"),
        ("트리거 목록 및 활성화 상태 비교",                "HIGH"),
        ("트리거 실행 순서 확인 (FOLLOWS/PRECEDES)",       "MEDIUM"),
        ("트리거 타입 확인 (BEFORE/AFTER/INSTEAD OF)",     "MEDIUM"),
        ("DDL 트리거 처리 방안 확인",                      "HIGH"),
        ("DB Link 접속 테스트 (tgt에서)",                  "HIGH"),
        ("DB Link 대상 호스트 IP 변경 여부 확인",          "HIGH"),
        ("DB Link를 사용하는 객체 목록 확인",              "HIGH"),
        ("DBMS_JOB 목록 확인 (소스)",                      "HIGH"),
        ("DBMS_JOB → DBMS_SCHEDULER 변환 계획 확인",       "HIGH"),
        ("DBMS_SCHEDULER Job 목록 비교 (tgt)",             "HIGH"),
        ("스케줄러 Job 활성화 상태 확인 (tgt)",            "HIGH"),
        ("스케줄러 실행 이력 확인 (tgt)",                  "MEDIUM"),
        ("파티션 테이블 익스텐트 크기 확인",               "MEDIUM"),
        ("파티션 인덱스 상태 확인 (USABLE/UNUSABLE)",      "HIGH"),
        ("파티션 Add/Drop DDL 복제 가능 여부 확인",        "HIGH"),
        ("Range 파티션 MAXVALUE 처리 확인",                "MEDIUM"),
        ("List 파티션 DEFAULT 처리 확인",                  "MEDIUM"),
        ("Hash 파티션 수 일치 여부 확인",                  "MEDIUM"),
        ("Interval 파티션 처리 확인",                      "HIGH"),
        ("GG DDL 복제 범위 확인 (TABLE 객체만)",           "HIGH"),
        ("GG DDL 필터 설정 확인",                          "HIGH"),
        ("DDL 히스토리 로그 설정 확인",                    "MEDIUM"),
        ("External Table 처리 방안 확인",                  "MEDIUM"),
        ("임시 테이블 (GTT) 처리 방안 확인",               "MEDIUM"),
        ("Advanced Queue (AQ) 처리 방안 확인",             "HIGH"),
        ("Java Stored Procedure 처리 방안 확인",           "MEDIUM"),
        ("Workspace Manager 사용 여부 확인",               "LOW"),
        ("Label Security 사용 여부 확인",                  "LOW"),
        ("Fine-Grained Auditing 설정 비교",                "MEDIUM"),
        ("Audit Trail 이관 계획 확인",                     "LOW"),
        ("통계 정보 (DBMS_STATS) 이관 확인",               "HIGH"),
        ("히스토그램 정보 비교",                           "MEDIUM"),
        ("Fixed Object 통계 수집 확인",                    "LOW"),
        ("AWR/ASH 데이터 이관 계획 확인",                  "LOW"),
        ("Recycle Bin 정리 확인",                          "LOW"),
        ("Redo Log 크기 및 그룹 수 확인 (tgt)",            "MEDIUM"),
    ],
    "05_Migration_Caution": [
        ("Oracle SE 미지원 기능 최종 확인",                "HIGH"),
        ("BITMAP 인덱스 미사용 확인",                      "HIGH"),
        ("Parallel DML 제한 확인 (SE)",                    "HIGH"),
        ("Advanced Compression 미사용 확인 (SE)",          "HIGH"),
        ("Partitioning 라이선스 확인 (SE2)",               "HIGH"),
        ("GoldenGate SE 제약 최종 확인",                   "HIGH"),
        ("GG Integrated Capture 가용 여부 확인",           "HIGH"),
        ("DDL 복제 제한 사항 문서화",                      "HIGH"),
        ("시퀀스 캐시로 인한 GAP 허용 여부 확인",         "MEDIUM"),
        ("UDT (User Defined Type) GG 복제 가능 여부",      "HIGH"),
        ("XML 타입 컬럼 GG 복제 가능 여부",                "HIGH"),
        ("LONG/LONG RAW 컬럼 처리 방안 확인",              "HIGH"),
        ("BFILE 컬럼 처리 방안 확인",                      "MEDIUM"),
        ("Deferred Constraint 처리 방안 확인",             "HIGH"),
        ("Supplemental Log 오버헤드 측정",                 "MEDIUM"),
        ("소스 DB I/O 증가율 모니터링",                    "MEDIUM"),
        ("RDS Parameter Group 변경 이력 확인",             "HIGH"),
        ("RDS 유지보수 윈도우 충돌 확인",                  "HIGH"),
        ("RDS 자동 백업과 expdp 시점 충돌 확인",           "HIGH"),
        ("FastConnect/VPN 대역폭 충분성 확인",             "HIGH"),
        ("OCI Security List / NSG 규칙 확인",              "HIGH"),
        ("OCI DBCS Backup 설정 확인",                      "HIGH"),
        ("롤백 절차 문서화 및 테스트 완료 확인",           "HIGH"),
        ("소스 RDS 2주 보존 계획 확인",                    "HIGH"),
        ("Cut-over 공지 및 다운타임 동의 확인",            "HIGH"),
        ("비상 연락망 확인",                               "HIGH"),
    ],
}


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class DomainSummary(BaseModel):
    domain: str
    total: int
    pass_count: int
    warn_count: int
    fail_count: int
    pending_count: int


class ValidationSummaryResponse(BaseModel):
    total: int
    pass_count: int
    warn_count: int
    fail_count: int
    pending_count: int
    go_nogo: str
    domain_summary: List[DomainSummary]


class ValidationItemResponse(BaseModel):
    id: int
    domain: str
    item_no: int
    item_name: str
    priority: str
    status: str
    note: Optional[str] = None
    assignee: Optional[str] = None
    verified_at: Optional[str] = None
    verified_by: Optional[str] = None


class ValidationUpdateRequest(BaseModel):
    status: Optional[str] = None
    note: Optional[str] = None
    assignee: Optional[str] = None


class VerifyRequest(BaseModel):
    status: str
    note: Optional[str] = None


# ---------------------------------------------------------------------------
# Go/No-Go logic
# ---------------------------------------------------------------------------

def compute_go_nogo(total: int, pass_count: int, warn_count: int, fail_count: int,
                    pending_count: int, high_all_pass: bool) -> str:
    if fail_count > 0:
        return "NO_GO"
    if pending_count > 0:
        return "PENDING"
    if pass_count == total:
        return "GO"
    if high_all_pass and warn_count > 0:
        return "CONDITIONAL_GO"
    return "PENDING"


# ---------------------------------------------------------------------------
# Seed logic
# ---------------------------------------------------------------------------

async def seed_validation_data() -> None:
    """Seed validation_results table from xlsx or dummy data if empty."""
    from core.db import get_db_path
    import aiosqlite as _aio

    async with _aio.connect(get_db_path()) as db:
        db.row_factory = _aio.Row
        row = await (await db.execute("SELECT COUNT(*) as cnt FROM validation_results")).fetchone()
        if row["cnt"] > 0:
            return

        xlsx_path = "/app/docs/00. validation_plan.xlsx"
        items: List[tuple] = []

        if os.path.exists(xlsx_path):
            try:
                items = _parse_xlsx(xlsx_path)
            except Exception:
                items = []

        if not items:
            items = _generate_dummy_items()

        await db.executemany(
            "INSERT INTO validation_results (domain, item_no, item_name, priority, status) VALUES (?,?,?,?,?)",
            items,
        )
        await db.commit()


def _parse_xlsx(path: str) -> List[tuple]:
    """Parse xlsx file and return list of (domain, item_no, item_name, priority, status)."""
    try:
        import openpyxl
    except ImportError:
        return []

    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    result: List[tuple] = []

    domain_map = {
        "01": "01_GG_Process",
        "gg": "01_GG_Process",
        "goldengate": "01_GG_Process",
        "02": "02_Static_Schema",
        "static": "02_Static_Schema",
        "schema": "02_Static_Schema",
        "03": "03_Data_Validation",
        "data": "03_Data_Validation",
        "validation": "03_Data_Validation",
        "04": "04_Special_Objects",
        "special": "04_Special_Objects",
        "objects": "04_Special_Objects",
        "05": "05_Migration_Caution",
        "caution": "05_Migration_Caution",
        "migration": "05_Migration_Caution",
    }

    priority_map = {
        "상": "HIGH", "high": "HIGH", "h": "HIGH",
        "중": "MEDIUM", "medium": "MEDIUM", "m": "MEDIUM",
        "하": "LOW", "low": "LOW", "l": "LOW",
    }

    for sheet_name in wb.sheetnames:
        # Determine domain from sheet name
        domain = None
        name_lower = sheet_name.lower().strip()
        for key, val in domain_map.items():
            if key in name_lower:
                domain = val
                break
        if domain is None:
            continue

        ws = wb[sheet_name]
        domain_counter: dict = {}
        if domain not in domain_counter:
            domain_counter[domain] = 0

        for i, row in enumerate(ws.iter_rows(values_only=True)):
            if i == 0:
                continue  # skip header
            if not row or all(c is None for c in row):
                continue

            # Try to extract item_name and priority from row
            item_name = None
            priority = "MEDIUM"

            for cell in row:
                if cell is None:
                    continue
                cell_str = str(cell).strip()
                if not item_name and len(cell_str) > 2 and not cell_str.isdigit():
                    item_name = cell_str
                # Priority detection
                pval = priority_map.get(cell_str.lower())
                if pval:
                    priority = pval

            if not item_name:
                continue

            domain_counter.setdefault(domain, 0)
            domain_counter[domain] += 1
            result.append((domain, domain_counter[domain], item_name, priority, "PENDING"))

    if not result:
        return []
    return result


def _generate_dummy_items() -> List[tuple]:
    """Generate dummy validation items from DOMAIN_ITEMS definition."""
    result: List[tuple] = []
    for domain, items_list in DOMAIN_ITEMS.items():
        for idx, (name, priority) in enumerate(items_list, start=1):
            result.append((domain, idx, name, priority, "PENDING"))
    return result


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/summary", response_model=ValidationSummaryResponse)
async def get_summary(db: aiosqlite.Connection = Depends(get_db)):
    # Overall counts
    row = await (await db.execute("""
        SELECT
            COUNT(*) as total,
            SUM(CASE WHEN status='PASS'    THEN 1 ELSE 0 END) as pass_count,
            SUM(CASE WHEN status='WARN'    THEN 1 ELSE 0 END) as warn_count,
            SUM(CASE WHEN status='FAIL'    THEN 1 ELSE 0 END) as fail_count,
            SUM(CASE WHEN status='PENDING' THEN 1 ELSE 0 END) as pending_count
        FROM validation_results
    """)).fetchone()

    total        = row["total"]        or 0
    pass_count   = row["pass_count"]   or 0
    warn_count   = row["warn_count"]   or 0
    fail_count   = row["fail_count"]   or 0
    pending_count= row["pending_count"] or 0

    # Check if all HIGH priority items pass
    high_row = await (await db.execute("""
        SELECT
            COUNT(*) as total_high,
            SUM(CASE WHEN status='PASS' THEN 1 ELSE 0 END) as high_pass
        FROM validation_results
        WHERE priority='HIGH'
    """)).fetchone()
    total_high = high_row["total_high"] or 0
    high_pass  = high_row["high_pass"]  or 0
    high_all_pass = (total_high > 0 and high_pass == total_high)

    go_nogo = compute_go_nogo(total, pass_count, warn_count, fail_count, pending_count, high_all_pass)

    # Domain breakdown
    domain_rows = await (await db.execute("""
        SELECT
            domain,
            COUNT(*) as total,
            SUM(CASE WHEN status='PASS'    THEN 1 ELSE 0 END) as pass_count,
            SUM(CASE WHEN status='WARN'    THEN 1 ELSE 0 END) as warn_count,
            SUM(CASE WHEN status='FAIL'    THEN 1 ELSE 0 END) as fail_count,
            SUM(CASE WHEN status='PENDING' THEN 1 ELSE 0 END) as pending_count
        FROM validation_results
        GROUP BY domain
        ORDER BY domain
    """)).fetchall()

    domain_summary = [
        DomainSummary(
            domain=r["domain"],
            total=r["total"] or 0,
            pass_count=r["pass_count"] or 0,
            warn_count=r["warn_count"] or 0,
            fail_count=r["fail_count"] or 0,
            pending_count=r["pending_count"] or 0,
        )
        for r in domain_rows
    ]

    return ValidationSummaryResponse(
        total=total,
        pass_count=pass_count,
        warn_count=warn_count,
        fail_count=fail_count,
        pending_count=pending_count,
        go_nogo=go_nogo,
        domain_summary=domain_summary,
    )


@router.get("/items", response_model=List[ValidationItemResponse])
async def list_items(
    domain:   Optional[str] = Query(None),
    priority: Optional[str] = Query(None),
    status:   Optional[str] = Query(None),
    db: aiosqlite.Connection = Depends(get_db),
):
    query = "SELECT * FROM validation_results WHERE 1=1"
    params: list = []
    if domain:
        query += " AND domain=?"
        params.append(domain)
    if priority:
        query += " AND priority=?"
        params.append(priority)
    if status:
        query += " AND status=?"
        params.append(status)
    query += " ORDER BY domain, item_no"

    rows = await (await db.execute(query, params)).fetchall()
    return [_row_to_item(r) for r in rows]


@router.get("/items/{item_id}", response_model=ValidationItemResponse)
async def get_item(item_id: int, db: aiosqlite.Connection = Depends(get_db)):
    row = await (
        await db.execute("SELECT * FROM validation_results WHERE id=?", (item_id,))
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="항목을 찾을 수 없습니다")
    return _row_to_item(row)


@router.patch("/items/{item_id}", response_model=ValidationItemResponse)
async def update_item(
    item_id: int,
    body: ValidationUpdateRequest,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    row = await (
        await db.execute("SELECT * FROM validation_results WHERE id=?", (item_id,))
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="항목을 찾을 수 없습니다")

    now = datetime.now(timezone.utc).isoformat()
    fields: list[str] = []
    params: list = []

    if body.status is not None:
        if body.status not in ("PASS", "WARN", "FAIL", "PENDING"):
            raise HTTPException(status_code=400, detail="status는 PASS|WARN|FAIL|PENDING 중 하나여야 합니다")
        fields += ["status=?", "verified_at=?", "verified_by=?"]
        params += [body.status, now, current_user.username]
    if body.note is not None:
        fields.append("note=?")
        params.append(body.note)
    if body.assignee is not None:
        fields.append("assignee=?")
        params.append(body.assignee)

    if not fields:
        return _row_to_item(row)

    params.append(item_id)
    await db.execute(f"UPDATE validation_results SET {', '.join(fields)} WHERE id=?", params)

    # event log
    if body.status is not None:
        await db.execute(
            """INSERT INTO event_log (event_type, message, related_item, actor, created_at)
               VALUES ('VALIDATION_UPDATE', ?, ?, ?, ?)""",
            (
                f"[{row['domain']}] {row['item_name']} 상태 변경: {row['status']} → {body.status}",
                str(item_id),
                current_user.username,
                now,
            ),
        )

    await db.commit()

    updated = await (
        await db.execute("SELECT * FROM validation_results WHERE id=?", (item_id,))
    ).fetchone()
    return _row_to_item(updated)


@router.post("/items/{item_id}/verify", response_model=ValidationItemResponse)
async def verify_item(
    item_id: int,
    body: VerifyRequest,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if body.status not in ("PASS", "WARN", "FAIL"):
        raise HTTPException(status_code=400, detail="status는 PASS|WARN|FAIL 중 하나여야 합니다")

    row = await (
        await db.execute("SELECT * FROM validation_results WHERE id=?", (item_id,))
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="항목을 찾을 수 없습니다")

    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        """UPDATE validation_results
           SET status=?, note=?, verified_at=?, verified_by=?
           WHERE id=?""",
        (body.status, body.note, now, current_user.username, item_id),
    )
    await db.execute(
        """INSERT INTO event_log (event_type, message, related_item, actor, created_at)
           VALUES ('VALIDATION_UPDATE', ?, ?, ?, ?)""",
        (
            f"[{row['domain']}] {row['item_name']} 검증 완료: {body.status}",
            str(item_id),
            current_user.username,
            now,
        ),
    )
    await db.commit()

    updated = await (
        await db.execute("SELECT * FROM validation_results WHERE id=?", (item_id,))
    ).fetchone()
    return _row_to_item(updated)


@router.get("/high-priority", response_model=List[ValidationItemResponse])
async def get_high_priority(db: aiosqlite.Connection = Depends(get_db)):
    rows = await (await db.execute(
        "SELECT * FROM validation_results WHERE priority='HIGH' ORDER BY domain, item_no"
    )).fetchall()
    return [_row_to_item(r) for r in rows]


@router.post("/seed")
async def manual_seed(
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="관리자 권한이 필요합니다")

    await db.execute("DELETE FROM validation_results")
    await db.commit()

    # Re-run seed
    from core.db import get_db_path
    import aiosqlite as _aio
    async with _aio.connect(get_db_path()) as db2:
        db2.row_factory = _aio.Row
        items = _generate_dummy_items()
        await db2.executemany(
            "INSERT INTO validation_results (domain, item_no, item_name, priority, status) VALUES (?,?,?,?,?)",
            items,
        )
        await db2.commit()

    return {"message": f"재시드 완료: {len(items)}개 항목"}


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _row_to_item(row: aiosqlite.Row) -> ValidationItemResponse:
    return ValidationItemResponse(
        id=row["id"],
        domain=row["domain"],
        item_no=row["item_no"],
        item_name=row["item_name"],
        priority=row["priority"],
        status=row["status"],
        note=row["note"],
        assignee=row["assignee"],
        verified_at=row["verified_at"],
        verified_by=row["verified_by"],
    )
