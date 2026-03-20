from fastapi import APIRouter, Depends, Query, HTTPException
from typing import List, Optional
from datetime import datetime
import aiosqlite

from core.db import get_db
from api.auth import get_current_user, UserInfo
from models.event import EventCreate, EventOut

router = APIRouter()


@router.get("", response_model=List[EventOut])
async def list_events(
    limit: int = Query(100, le=500),
    offset: int = 0,
    event_type: Optional[str] = None,
    date: Optional[str] = None,  # YYYY-MM-DD 필터
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
):
    conditions = []
    params: list = []

    if event_type:
        conditions.append("event_type=?")
        params.append(event_type)
    if date:
        conditions.append("created_at LIKE ?")
        params.append(f"{date}%")

    where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
    params += [limit, offset]

    rows = await (
        await db.execute(
            f"SELECT * FROM event_log {where} ORDER BY created_at DESC LIMIT ? OFFSET ?",
            params,
        )
    ).fetchall()
    return [EventOut(**dict(r)) for r in rows]


@router.post("", response_model=EventOut)
async def create_event(
    body: EventCreate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    now = datetime.utcnow().isoformat()
    cur = await db.execute(
        "INSERT INTO event_log "
        "(event_type, message, related_script, related_item, actor, created_at) "
        "VALUES (?,?,?,?,?,?)",
        (
            body.event_type,
            body.message,
            body.related_script,
            body.related_item,
            current_user.username,
            now,
        ),
    )
    await db.commit()
    row = await (
        await db.execute("SELECT * FROM event_log WHERE id=?", (cur.lastrowid,))
    ).fetchone()
    return EventOut(**dict(row))


@router.post("/{event_id}/confirm")
async def confirm_event(
    event_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    row = await (
        await db.execute("SELECT id FROM event_log WHERE id=?", (event_id,))
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="이벤트를 찾을 수 없습니다")
    now = datetime.utcnow().isoformat()
    await db.execute(
        "UPDATE event_log SET confirmed_by=?, confirmed_at=? WHERE id=?",
        (current_user.username, now, event_id),
    )
    await db.commit()
    return {"status": "confirmed", "event_id": event_id}
