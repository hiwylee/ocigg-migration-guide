from fastapi import APIRouter, Depends, HTTPException
from typing import List
from datetime import datetime
import os
import aiosqlite
import httpx

from core.env_loader import settings
from core.db import get_db
from api.auth import get_current_user, UserInfo
from models.config_entry import ConfigEntry, ConfigUpdate

router = APIRouter()


@router.get("", response_model=List[ConfigEntry])
async def list_config(
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
):
    rows = await (
        await db.execute(
            "SELECT key, value, locked, changed_by, changed_at "
            "FROM config_registry ORDER BY key"
        )
    ).fetchall()
    return [
        ConfigEntry(
            key=r["key"],
            value=r["value"],
            locked=bool(r["locked"]),
            changed_by=r["changed_by"],
            changed_at=r["changed_at"],
        )
        for r in rows
    ]


@router.get("/{key}", response_model=ConfigEntry)
async def get_config(
    key: str,
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
):
    row = await (
        await db.execute(
            "SELECT key, value, locked, changed_by, changed_at "
            "FROM config_registry WHERE key=?",
            (key,),
        )
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"키 '{key}'를 찾을 수 없습니다")
    return ConfigEntry(
        key=row["key"],
        value=row["value"],
        locked=bool(row["locked"]),
        changed_by=row["changed_by"],
        changed_at=row["changed_at"],
    )


@router.put("/{key}", response_model=ConfigEntry)
async def update_config(
    key: str,
    body: ConfigUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    row = await (
        await db.execute(
            "SELECT locked FROM config_registry WHERE key=?", (key,)
        )
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"키 '{key}'를 찾을 수 없습니다")
    if row["locked"]:
        raise HTTPException(status_code=403, detail=f"키 '{key}'는 잠금 상태입니다")

    now = datetime.utcnow().isoformat()
    await db.execute(
        "UPDATE config_registry SET value=?, changed_by=?, changed_at=? WHERE key=?",
        (body.value, current_user.username, now, key),
    )
    await db.commit()
    return await get_config(key, db, current_user)


@router.post("/{key}/lock")
async def lock_config(
    key: str,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if current_user.role not in ("admin", "migration_leader"):
        raise HTTPException(status_code=403, detail="권한이 없습니다 (admin/migration_leader 필요)")
    row = await (
        await db.execute("SELECT key FROM config_registry WHERE key=?", (key,))
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"키 '{key}'를 찾을 수 없습니다")
    await db.execute("UPDATE config_registry SET locked=1 WHERE key=?", (key,))
    await db.commit()
    return {"status": "locked", "key": key}


@router.post("/healthcheck")
async def healthcheck(
    _: UserInfo = Depends(get_current_user),
):
    """Source DB / Target DB / GoldenGate 연결 상태 확인"""
    results: dict = {}

    # Source DB
    try:
        import oracledb
        dsn = (
            f"{settings.SRC_DB_HOST}:{settings.SRC_DB_PORT}"
            f"/{settings.SRC_DB_SERVICE or settings.SRC_DB_SID}"
        )
        conn = oracledb.connect(
            user=settings.SRC_DBA_USER,
            password=settings.SRC_DBA_PASS,
            dsn=dsn,
        )
        conn.close()
        results["source_db"] = {"status": "ok", "dsn": dsn}
    except Exception as e:
        results["source_db"] = {"status": "error", "detail": str(e)}

    # Target DB
    try:
        import oracledb
        dsn = (
            f"{settings.TGT_DB_HOST}:{settings.TGT_DB_PORT}"
            f"/{settings.TGT_DB_SERVICE or settings.TGT_DB_SID}"
        )
        conn = oracledb.connect(
            user=settings.TGT_DBA_USER,
            password=settings.TGT_DBA_PASS,
            dsn=dsn,
        )
        conn.close()
        results["target_db"] = {"status": "ok", "dsn": dsn}
    except Exception as e:
        results["target_db"] = {"status": "error", "detail": str(e)}

    # GoldenGate Admin Server
    if not settings.GG_ADMIN_URL:
        results["goldengate"] = {"status": "not_configured"}
    else:
        try:
            verify: bool | str = (
                settings.GG_CA_BUNDLE
                if os.path.exists(settings.GG_CA_BUNDLE)
                else True
            )
            async with httpx.AsyncClient(verify=verify, timeout=10.0) as client:
                resp = await client.get(
                    f"{settings.GG_ADMIN_URL}/services/v2/deployments",
                    auth=(settings.GG_ADMIN_USER, settings.GG_ADMIN_PASS),
                )
            results["goldengate"] = {
                "status": "ok" if resp.status_code < 400 else "error",
                "http_status": resp.status_code,
            }
        except Exception as e:
            results["goldengate"] = {"status": "error", "detail": str(e)}

    return results
