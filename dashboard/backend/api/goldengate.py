"""
GoldenGate Monitor API
prefix: /api/gg
"""
from __future__ import annotations

from datetime import datetime, timezone, timedelta
from typing import Optional

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query

from api.auth import UserInfo, get_current_user
from core.db import get_db
from core.env_loader import settings

router = APIRouter()

# 프로세스 제어 허용 역할
_OPERATOR_ROLES = {"gg_operator", "admin", "migration_leader"}


def _gg_configured() -> bool:
    return bool(settings.GG_ADMIN_URL)


def _require_gg():
    if not _gg_configured():
        raise HTTPException(
            status_code=404,
            detail={"configured": False, "message": "GG_ADMIN_URL이 설정되지 않았습니다"},
        )


# ---------------------------------------------------------------------------
# GET /api/gg/status
# ---------------------------------------------------------------------------

@router.get("/status")
async def gg_status(
    current_user: UserInfo = Depends(get_current_user),
):
    """전체 프로세스 상태 (EXT1/PUMP1/REP1)"""
    if not _gg_configured():
        return {"configured": False, "processes": []}

    from core.gg_client import get_all_processes, GGClientError, NotConfiguredError

    try:
        processes = await get_all_processes()
    except NotConfiguredError:
        return {"configured": False, "processes": []}
    except GGClientError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    return {"configured": True, "processes": processes}


# ---------------------------------------------------------------------------
# GET /api/gg/lag-history
# ---------------------------------------------------------------------------

@router.get("/lag-history")
async def lag_history(
    hours: int = Query(default=24, ge=1, le=168),
    process: Optional[str] = Query(default=None),
    current_user: UserInfo = Depends(get_current_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """lag_history 테이블 조회 (최근 N시간)"""
    since = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()

    if process:
        cursor = await db.execute(
            """SELECT process_name, lag_seconds, recorded_at
               FROM lag_history
               WHERE recorded_at >= ? AND process_name = ?
               ORDER BY recorded_at ASC""",
            (since, process),
        )
    else:
        cursor = await db.execute(
            """SELECT process_name, lag_seconds, recorded_at
               FROM lag_history
               WHERE recorded_at >= ?
               ORDER BY recorded_at ASC""",
            (since,),
        )

    rows = await cursor.fetchall()
    return [
        {
            "process_name": row["process_name"],
            "lag_seconds": row["lag_seconds"],
            "recorded_at": row["recorded_at"],
        }
        for row in rows
    ]


# ---------------------------------------------------------------------------
# GET /api/gg/discard-count
# ---------------------------------------------------------------------------

@router.get("/discard-count")
async def discard_count(
    current_user: UserInfo = Depends(get_current_user),
):
    """Discard 레코드 수"""
    _require_gg()

    from core.gg_client import get_discard_count, GGClientError, NotConfiguredError

    try:
        count = await get_discard_count(settings.GG_REPLICAT_NAME)
    except NotConfiguredError:
        return {"configured": False, "count": 0}
    except GGClientError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    return {"replicat": settings.GG_REPLICAT_NAME, "count": count}


# ---------------------------------------------------------------------------
# GET /api/gg/error-log
# ---------------------------------------------------------------------------

@router.get("/error-log")
async def error_log(
    lines: int = Query(default=50, ge=1, le=500),
    current_user: UserInfo = Depends(get_current_user),
):
    """GG 에러 로그 마지막 N줄"""
    _require_gg()

    from core.gg_client import get_error_log, GGClientError, NotConfiguredError

    try:
        log_lines = await get_error_log(lines)
    except NotConfiguredError:
        return {"configured": False, "lines": []}
    except GGClientError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    return {"lines": log_lines, "count": len(log_lines)}


# ---------------------------------------------------------------------------
# POST /api/gg/process/{name}/start|stop|kill
# ---------------------------------------------------------------------------

def _require_operator(current_user: UserInfo) -> None:
    if current_user.role not in _OPERATOR_ROLES:
        raise HTTPException(status_code=403, detail="gg_operator 이상 역할이 필요합니다")


@router.post("/process/{name}/start")
async def process_start(
    name: str,
    current_user: UserInfo = Depends(get_current_user),
):
    """프로세스 시작"""
    _require_gg()
    _require_operator(current_user)

    from core.gg_client import start_process, GGClientError, NotConfiguredError

    try:
        result = await start_process(name)
    except NotConfiguredError:
        return {"configured": False}
    except GGClientError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    return result


@router.post("/process/{name}/stop")
async def process_stop(
    name: str,
    current_user: UserInfo = Depends(get_current_user),
):
    """프로세스 중지"""
    _require_gg()
    _require_operator(current_user)

    from core.gg_client import stop_process, GGClientError, NotConfiguredError

    try:
        result = await stop_process(name)
    except NotConfiguredError:
        return {"configured": False}
    except GGClientError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    return result


@router.post("/process/{name}/kill")
async def process_kill(
    name: str,
    current_user: UserInfo = Depends(get_current_user),
):
    """프로세스 강제 종료"""
    _require_gg()
    _require_operator(current_user)

    from core.gg_client import kill_process, GGClientError, NotConfiguredError

    try:
        result = await kill_process(name)
    except NotConfiguredError:
        return {"configured": False}
    except GGClientError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    return result


# ---------------------------------------------------------------------------
# GET /api/gg/lag-stable
# ---------------------------------------------------------------------------

@router.get("/lag-stable")
async def lag_stable(
    current_user: UserInfo = Depends(get_current_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """
    24h 안정화 여부 조회.
    lag_history에서 최근 24h 동안 LAG > LAG_CRITICAL_SECONDS 가 없으면 stable=True.
    config_registry의 LAG_STABLE_SINCE 키도 참조.
    """
    threshold = settings.LAG_CRITICAL_SECONDS
    since_24h = (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat()

    # 최근 24h 안에 임계 초과 LAG 존재 여부
    cursor = await db.execute(
        """SELECT COUNT(*) as cnt
           FROM lag_history
           WHERE recorded_at >= ? AND lag_seconds > ?""",
        (since_24h, threshold),
    )
    row = await cursor.fetchone()
    has_violation = (row["cnt"] if row else 0) > 0

    # config_registry에서 LAG_STABLE_SINCE 조회
    cfg_cursor = await db.execute(
        "SELECT value FROM config_registry WHERE key='LAG_STABLE_SINCE'",
    )
    cfg_row = await cfg_cursor.fetchone()
    stable_since: Optional[str] = cfg_row["value"] if cfg_row else None

    # 첫 데이터 존재 시각 조회 (연속성 계산용)
    first_cursor = await db.execute(
        "SELECT MIN(recorded_at) as first_at FROM lag_history WHERE recorded_at >= ?",
        (since_24h,),
    )
    first_row = await first_cursor.fetchone()
    first_at: Optional[str] = first_row["first_at"] if first_row else None

    if has_violation:
        # 임계 초과 발생 → 안정화 기산점 리셋
        await db.execute(
            "UPDATE config_registry SET value='' WHERE key='LAG_STABLE_SINCE'",
        )
        await db.commit()
        stable_since = None

    # 안정화 여부 및 경과 시간 계산
    stable = False
    hours_elapsed: float = 0.0

    if not has_violation and stable_since:
        try:
            since_dt = datetime.fromisoformat(stable_since)
            if since_dt.tzinfo is None:
                since_dt = since_dt.replace(tzinfo=timezone.utc)
            elapsed = (datetime.now(timezone.utc) - since_dt).total_seconds() / 3600
            hours_elapsed = round(elapsed, 2)
            stable = elapsed >= 24.0
        except ValueError:
            pass
    elif not has_violation and first_at and not stable_since:
        # 안정화 기산점 미설정이지만 위반 없음 → 지금을 기산점으로 설정
        now_iso = datetime.now(timezone.utc).isoformat()
        await db.execute(
            "UPDATE config_registry SET value=? WHERE key='LAG_STABLE_SINCE'",
            (now_iso,),
        )
        await db.commit()
        stable_since = now_iso

    return {
        "stable": stable,
        "since": stable_since or None,
        "hours_elapsed": hours_elapsed,
        "threshold_seconds": threshold,
    }
