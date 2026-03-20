from __future__ import annotations

import logging
from datetime import datetime, timezone

import aiosqlite
from apscheduler.schedulers.asyncio import AsyncIOScheduler

from core.db import get_db_path
from core.env_loader import settings

logger = logging.getLogger(__name__)

scheduler = AsyncIOScheduler(timezone="UTC")


def start_scheduler() -> None:
    if not scheduler.running:
        scheduler.start()


def stop_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)


# ---------------------------------------------------------------------------
# Job functions
# ---------------------------------------------------------------------------

async def collect_lag_history() -> None:
    """5분 간격: EXT1/PUMP1/REP1 LAG을 lag_history 테이블에 INSERT"""
    from core.gg_client import get_all_processes, NotConfiguredError, GGClientError

    try:
        processes = await get_all_processes()
    except NotConfiguredError:
        return
    except GGClientError as exc:
        logger.warning("collect_lag_history: GGClientError – %s", exc)
        return
    except Exception as exc:
        logger.error("collect_lag_history: unexpected error – %s", exc)
        return

    now = datetime.now(timezone.utc).isoformat()
    try:
        async with aiosqlite.connect(get_db_path()) as db:
            for proc in processes:
                await db.execute(
                    "INSERT INTO lag_history (process_name, lag_seconds, recorded_at) VALUES (?,?,?)",
                    (proc["name"], proc.get("lag_seconds"), now),
                )
            await db.commit()
    except Exception as exc:
        logger.error("collect_lag_history: DB write error – %s", exc)


async def check_gg_health() -> None:
    """30초 간격: ABEND 감지 시 alerts 테이블에 CRITICAL INSERT"""
    from core.gg_client import get_all_processes, NotConfiguredError, GGClientError

    try:
        processes = await get_all_processes()
    except NotConfiguredError:
        return
    except GGClientError as exc:
        logger.warning("check_gg_health: GGClientError – %s", exc)
        return
    except Exception as exc:
        logger.error("check_gg_health: unexpected error – %s", exc)
        return

    abended = [p["name"] for p in processes if p.get("status") == "ABEND"]
    if not abended:
        return

    now = datetime.now(timezone.utc).isoformat()
    message = f"GoldenGate ABEND 감지: {', '.join(abended)}"
    try:
        async with aiosqlite.connect(get_db_path()) as db:
            # 동일 메시지가 최근 5분 내 이미 삽입된 경우 중복 방지
            existing = await (
                await db.execute(
                    """SELECT id FROM alerts
                       WHERE level='CRITICAL' AND message=?
                         AND created_at >= datetime('now', '-5 minutes')""",
                    (message,),
                )
            ).fetchone()
            if not existing:
                await db.execute(
                    "INSERT INTO alerts (level, message, created_at) VALUES (?,?,?)",
                    ("CRITICAL", message, now),
                )
                await db.commit()
                logger.warning("check_gg_health: ABEND alert inserted – %s", message)
    except Exception as exc:
        logger.error("check_gg_health: DB write error – %s", exc)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

def setup_jobs() -> None:
    """GG_ADMIN_URL이 설정된 경우에만 LAG 수집 및 헬스체크 job 등록"""
    if not settings.GG_ADMIN_URL:
        logger.info("setup_jobs: GG_ADMIN_URL 미설정 — GG 관련 job 건너뜀")
        return

    scheduler.add_job(
        collect_lag_history,
        trigger="interval",
        minutes=5,
        id="collect_lag_history",
        replace_existing=True,
        max_instances=1,
        name="GG LAG 수집 (5분 간격)",
    )

    scheduler.add_job(
        check_gg_health,
        trigger="interval",
        seconds=30,
        id="check_gg_health",
        replace_existing=True,
        max_instances=1,
        name="GG 헬스체크 (30초 간격)",
    )

    logger.info("setup_jobs: collect_lag_history(5m) + check_gg_health(30s) 등록 완료")
