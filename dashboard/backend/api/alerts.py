from fastapi import APIRouter, Depends, Query, HTTPException
from typing import List, Optional
from datetime import datetime, timezone
import aiosqlite
from pydantic import BaseModel

from core.db import get_db
from api.auth import get_current_user, UserInfo

router = APIRouter()


class AlertOut(BaseModel):
    id: int
    level: str
    message: str
    confirmed_by: Optional[str] = None
    confirmed_at: Optional[str] = None
    created_at: str


@router.get("", response_model=List[AlertOut])
async def list_alerts(
    unconfirmed_only: bool = Query(False),
    limit: int = Query(50, le=200),
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
):
    where = "WHERE confirmed_at IS NULL" if unconfirmed_only else ""
    rows = await (
        await db.execute(
            f"SELECT * FROM alerts {where} ORDER BY created_at DESC LIMIT ?",
            (limit,),
        )
    ).fetchall()
    return [AlertOut(**dict(r)) for r in rows]


@router.post("/{alert_id}/confirm")
async def confirm_alert(
    alert_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    row = await (
        await db.execute("SELECT id FROM alerts WHERE id=?", (alert_id,))
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="알림을 찾을 수 없습니다")
    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        "UPDATE alerts SET confirmed_by=?, confirmed_at=? WHERE id=?",
        (current_user.username, now, alert_id),
    )
    await db.commit()
    return {"status": "confirmed", "alert_id": alert_id}
