from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from datetime import datetime, timezone
import aiosqlite
from pydantic import BaseModel

from core.db import get_db
from api.auth import get_current_user, UserInfo

router = APIRouter()

CUTOVER_STEPS = [
    {"step_id": "step-1",  "title": "소스 DB 애플리케이션 세션 차단"},
    {"step_id": "step-2",  "title": "소스 DBMS_JOB BROKEN 처리"},
    {"step_id": "step-3",  "title": "소스 CURRENT_SCN 최종 기록"},
    {"step_id": "step-4",  "title": "GG LAG = 0 확인 대기"},
    {"step_id": "step-5",  "title": "Replicat 중지 및 HANDLECOLLISIONS 확인"},
    {"step_id": "step-6",  "title": "타겟 DB 최종 데이터 검증"},
    {"step_id": "step-7",  "title": "Trigger 재활성화"},
    {"step_id": "step-8",  "title": "FK Constraint 재활성화 + GG 프로세스 완전 중지"},
    {"step_id": "step-9",  "title": "DBMS_SCHEDULER JOB 활성화 + DB Link 확인"},
    {"step_id": "step-10", "title": "애플리케이션 연결 전환 + 서비스 검증"},
]


class StepComplete(BaseModel):
    note: Optional[str] = None


class RollbackStart(BaseModel):
    reason: str


async def _get_config(db: aiosqlite.Connection, key: str) -> Optional[str]:
    row = await (
        await db.execute("SELECT value FROM config_registry WHERE key=?", (key,))
    ).fetchone()
    return row["value"] if row else None


async def _set_config(db: aiosqlite.Connection, key: str, value: str, actor: str) -> None:
    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        "INSERT OR REPLACE INTO config_registry (key, value, locked, changed_by, changed_at) "
        "VALUES (?, ?, 0, ?, ?)",
        (key, value, actor, now),
    )


@router.get("/status")
async def get_cutover_status(
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
):
    started_at = await _get_config(db, "CUTOVER_STARTED_AT")
    rollback_started_at = await _get_config(db, "ROLLBACK_STARTED_AT")
    rollback_reason = await _get_config(db, "ROLLBACK_REASON")

    # step progress
    rows = await (
        await db.execute(
            "SELECT step_id, completed, completed_by, completed_at FROM step_progress WHERE filename='cutover'"
        )
    ).fetchall()
    completed_map = {r["step_id"]: dict(r) for r in rows}

    steps = []
    for s in CUTOVER_STEPS:
        prog = completed_map.get(s["step_id"])
        steps.append({
            **s,
            "completed": bool(prog["completed"]) if prog else False,
            "completed_by": prog["completed_by"] if prog else None,
            "completed_at": prog["completed_at"] if prog else None,
        })

    return {
        "started_at": started_at or None,
        "rollback_started_at": rollback_started_at or None,
        "rollback_reason": rollback_reason or None,
        "steps": steps,
    }


@router.post("/start")
async def start_cutover(
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if current_user.role not in ("admin", "migration_leader"):
        raise HTTPException(status_code=403, detail="admin 또는 migration_leader 권한 필요")
    existing = await _get_config(db, "CUTOVER_STARTED_AT")
    if existing:
        raise HTTPException(status_code=409, detail="Cut-over가 이미 시작되었습니다")
    now = datetime.now(timezone.utc).isoformat()
    await _set_config(db, "CUTOVER_STARTED_AT", now, current_user.username)
    await db.commit()

    # event log에 기록
    await db.execute(
        "INSERT INTO event_log (event_type, message, actor, created_at) VALUES (?,?,?,?)",
        ("CUTOVER_START", "Cut-over 실행 시작", current_user.username, now),
    )
    await db.commit()
    return {"status": "started", "started_at": now}


@router.post("/steps/{step_id}/complete")
async def complete_step(
    step_id: str,
    body: StepComplete,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    valid_ids = {s["step_id"] for s in CUTOVER_STEPS}
    if step_id not in valid_ids:
        raise HTTPException(status_code=404, detail=f"단계 '{step_id}'를 찾을 수 없습니다")
    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        "INSERT INTO step_progress (filename, step_id, completed, completed_by, completed_at) "
        "VALUES ('cutover', ?, 1, ?, ?) "
        "ON CONFLICT(filename, step_id) DO UPDATE SET completed=1, completed_by=excluded.completed_by, completed_at=excluded.completed_at",
        (step_id, current_user.username, now),
    )
    await db.commit()
    return {"status": "completed", "step_id": step_id}


@router.post("/steps/{step_id}/undo")
async def undo_step(
    step_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    await db.execute(
        "UPDATE step_progress SET completed=0, completed_by=NULL, completed_at=NULL "
        "WHERE filename='cutover' AND step_id=?",
        (step_id,),
    )
    await db.commit()
    return {"status": "undone", "step_id": step_id}


@router.post("/rollback")
async def start_rollback(
    body: RollbackStart,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if current_user.role not in ("admin", "migration_leader"):
        raise HTTPException(status_code=403, detail="admin 또는 migration_leader 권한 필요")
    now = datetime.now(timezone.utc).isoformat()
    await _set_config(db, "ROLLBACK_STARTED_AT", now, current_user.username)
    await _set_config(db, "ROLLBACK_REASON", body.reason, current_user.username)
    await db.commit()

    await db.execute(
        "INSERT INTO event_log (event_type, message, actor, created_at) VALUES (?,?,?,?)",
        ("ROLLBACK_START", f"롤백 시작: {body.reason}", current_user.username, now),
    )
    await db.commit()
    return {"status": "rollback_started", "started_at": now}
