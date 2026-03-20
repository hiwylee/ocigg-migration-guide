"""
Oracle DB 연결 클라이언트 (python-oracledb Thin 모드)
Thin 모드이므로 oracledb.init_oracle_client() 호출 없음.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any

try:
    import oracledb
    _ORACLEDB_AVAILABLE = True
except ImportError:
    _ORACLEDB_AVAILABLE = False

from core.env_loader import settings

logger = logging.getLogger(__name__)


def _build_dsn(host: str, port: int, service: str, sid: str) -> str:
    """service 우선, 없으면 SID로 DSN 생성."""
    if service:
        return f"{host}:{port}/{service}"
    if sid:
        return f"{host}:{port}/{sid}"
    return f"{host}:{port}"


def _get_src_dsn() -> str:
    return _build_dsn(
        settings.SRC_DB_HOST,
        settings.SRC_DB_PORT,
        settings.SRC_DB_SERVICE,
        settings.SRC_DB_SID,
    )


def _get_tgt_dsn() -> str:
    return _build_dsn(
        settings.TGT_DB_HOST,
        settings.TGT_DB_PORT,
        settings.TGT_DB_SERVICE,
        settings.TGT_DB_SID,
    )


async def execute_query(
    dsn: str,
    user: str,
    password: str,
    sql: str,
    params: dict | list | None = None,
    timeout: int = 10,
) -> list[dict[str, Any]]:
    """
    Oracle DB에 접속하여 쿼리를 실행하고 결과를 list[dict]로 반환.
    연결 실패 또는 쿼리 오류 시 RuntimeError 를 raise.
    """
    if not _ORACLEDB_AVAILABLE:
        raise RuntimeError("python-oracledb 패키지가 설치되지 않았습니다")

    if not dsn or not user:
        raise RuntimeError("DB 접속 정보(DSN/USER)가 설정되지 않았습니다")

    def _run() -> list[dict[str, Any]]:
        try:
            conn = oracledb.connect(
                user=user,
                password=password,
                dsn=dsn,
                mode=oracledb.DEFAULT_AUTH,
            )
            with conn:
                with conn.cursor() as cur:
                    if params:
                        cur.execute(sql, params)
                    else:
                        cur.execute(sql)
                    columns = [col[0] for col in cur.description]
                    rows = cur.fetchall()
                    return [dict(zip(columns, row)) for row in rows]
        except oracledb.DatabaseError as e:
            (error,) = e.args
            raise RuntimeError(f"Oracle DB 오류: {error.message}") from e
        except Exception as e:
            raise RuntimeError(f"DB 연결 실패: {str(e)}") from e

    loop = asyncio.get_event_loop()
    try:
        result = await asyncio.wait_for(
            loop.run_in_executor(None, _run),
            timeout=timeout,
        )
        return result
    except asyncio.TimeoutError:
        raise RuntimeError(f"DB 쿼리 타임아웃 ({timeout}초 초과)")


async def execute_query_src(
    sql: str,
    params: dict | list | None = None,
    timeout: int = 10,
) -> list[dict[str, Any]]:
    """Source DB (AWS RDS) 쿼리 실행."""
    return await execute_query(
        dsn=_get_src_dsn(),
        user=settings.SRC_DBA_USER,
        password=settings.SRC_DBA_PASS,
        sql=sql,
        params=params,
        timeout=timeout,
    )


async def execute_query_tgt(
    sql: str,
    params: dict | list | None = None,
    timeout: int = 10,
) -> list[dict[str, Any]]:
    """Target DB (OCI DBCS) 쿼리 실행."""
    return await execute_query(
        dsn=_get_tgt_dsn(),
        user=settings.TGT_DBA_USER,
        password=settings.TGT_DBA_PASS,
        sql=sql,
        params=params,
        timeout=timeout,
    )
