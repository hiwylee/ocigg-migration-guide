"""
DB 상태 비교 API
Source (AWS RDS Oracle SE) ↔ Target (OCI DBCS Oracle SE) 파라미터/오브젝트 수 비교.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from api.auth import get_current_user, UserInfo
from core.oracle_client import execute_query_src, execute_query_tgt

logger = logging.getLogger(__name__)
router = APIRouter()


# ─── 상수 ────────────────────────────────────────────────────────────────────

# 비교할 DB 파라미터 목록 (v$parameter 또는 v$nls_parameters)
_PARAM_NAMES = [
    "NLS_CHARACTERSET",
    "NLS_NCHAR_CHARACTERSET",
    "DB_TIMEZONE",
    "STREAMS_POOL_SIZE",
    "ENABLE_GOLDENGATE_REPLICATION",
    "LOG_MODE",
    "VERSION",
    "PLATFORM_NAME",
]

# 오브젝트 종류별 카운트 쿼리
_OBJECT_TYPE_MAP = {
    "TABLES":          "SELECT COUNT(*) CNT FROM dba_tables WHERE owner NOT IN ('SYS','SYSTEM','AUDSYS','OUTLN','DBSNMP')",
    "INDEXES":         "SELECT COUNT(*) CNT FROM dba_indexes WHERE owner NOT IN ('SYS','SYSTEM','AUDSYS','OUTLN','DBSNMP')",
    "CONSTRAINTS":     "SELECT COUNT(*) CNT FROM dba_constraints WHERE owner NOT IN ('SYS','SYSTEM','AUDSYS','OUTLN','DBSNMP') AND constraint_type IN ('P','U','R','C')",
    "SEQUENCES":       "SELECT COUNT(*) CNT FROM dba_sequences WHERE sequence_owner NOT IN ('SYS','SYSTEM','AUDSYS','OUTLN','DBSNMP')",
    "TRIGGERS":        "SELECT COUNT(*) CNT FROM dba_triggers WHERE owner NOT IN ('SYS','SYSTEM','AUDSYS','OUTLN','DBSNMP')",
    "PROCEDURES":      "SELECT COUNT(*) CNT FROM dba_procedures WHERE owner NOT IN ('SYS','SYSTEM','AUDSYS','OUTLN','DBSNMP')",
    "INVALID_OBJECTS": "SELECT COUNT(*) CNT FROM dba_objects WHERE status='INVALID' AND owner NOT IN ('SYS','SYSTEM','AUDSYS','OUTLN','DBSNMP')",
}


# ─── 응답 모델 ────────────────────────────────────────────────────────────────

class ParamCompareRow(BaseModel):
    param: str
    source_value: Optional[str]
    target_value: Optional[str]
    match: bool


class SessionCount(BaseModel):
    source: Optional[int]
    target: Optional[int]
    recorded_at: str


class SchemaDiffRow(BaseModel):
    object_type: str
    source_count: Optional[int]
    target_count: Optional[int]
    diff: Optional[int]


# ─── 유틸 ─────────────────────────────────────────────────────────────────────

def _param_query() -> str:
    """NLS + v$parameter + v$database + v$instance 를 UNION으로 합쳐 파라미터 값 조회."""
    return """
SELECT name, value FROM (
  SELECT UPPER(parameter) AS name, value FROM nls_database_parameters
  UNION ALL
  SELECT UPPER(name) AS name, value FROM v$parameter
  UNION ALL
  SELECT 'LOG_MODE'     AS name, log_mode     FROM v$database
  UNION ALL
  SELECT 'VERSION'      AS name, version      FROM v$instance
  UNION ALL
  SELECT 'PLATFORM_NAME' AS name, platform_name FROM v$database
  UNION ALL
  SELECT 'DB_TIMEZONE'  AS name, dbtimezone   FROM dual
)
WHERE name IN (
  'NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET','DB_TIMEZONE',
  'STREAMS_POOL_SIZE','ENABLE_GOLDENGATE_REPLICATION',
  'LOG_MODE','VERSION','PLATFORM_NAME'
)
"""


async def _fetch_params(fetch_fn) -> dict[str, str]:
    """파라미터 조회. 실패 시 빈 dict 반환."""
    try:
        rows = await fetch_fn(_param_query())
        result: dict[str, str] = {}
        for row in rows:
            name = str(row.get("NAME") or row.get("name") or "").upper()
            val = str(row.get("VALUE") or row.get("value") or "")
            if name and name not in result:
                result[name] = val
        return result
    except Exception as e:
        logger.warning("파라미터 조회 실패: %s", e)
        return {}


async def _fetch_object_count(fetch_fn, sql: str) -> Optional[int]:
    """오브젝트 수 쿼리. 실패 시 None 반환."""
    try:
        rows = await fetch_fn(sql)
        if rows:
            cnt = rows[0].get("CNT") or rows[0].get("cnt")
            return int(cnt) if cnt is not None else None
    except Exception as e:
        logger.warning("오브젝트 수 조회 실패: %s", e)
    return None


async def _fetch_session_count(fetch_fn) -> Optional[int]:
    sql = "SELECT COUNT(*) CNT FROM v$session WHERE type='USER' AND status='ACTIVE'"
    try:
        rows = await fetch_fn(sql)
        if rows:
            cnt = rows[0].get("CNT") or rows[0].get("cnt")
            return int(cnt) if cnt is not None else None
    except Exception as e:
        logger.warning("세션 수 조회 실패: %s", e)
    return None


# ─── 엔드포인트 ───────────────────────────────────────────────────────────────

@router.get("/compare", response_model=list[ParamCompareRow])
async def compare_params(
    _: UserInfo = Depends(get_current_user),
) -> list[ParamCompareRow]:
    """Source / Target DB 주요 파라미터 비교."""
    src_params, tgt_params = await asyncio.gather(
        _fetch_params(execute_query_src),
        _fetch_params(execute_query_tgt),
    )

    rows: list[ParamCompareRow] = []
    for param in _PARAM_NAMES:
        src_val = src_params.get(param, None) if src_params else None
        tgt_val = tgt_params.get(param, None) if tgt_params else None

        src_display = src_val if src_params else "연결 오류"
        tgt_display = tgt_val if tgt_params else "연결 오류"

        match = (src_display == tgt_display) if (src_params and tgt_params) else False

        rows.append(ParamCompareRow(
            param=param,
            source_value=src_display,
            target_value=tgt_display,
            match=match,
        ))

    return rows


@router.get("/session-count", response_model=SessionCount)
async def session_count(
    _: UserInfo = Depends(get_current_user),
) -> SessionCount:
    """Source / Target 활성 세션 수."""
    src_cnt, tgt_cnt = await asyncio.gather(
        _fetch_session_count(execute_query_src),
        _fetch_session_count(execute_query_tgt),
    )
    return SessionCount(
        source=src_cnt,
        target=tgt_cnt,
        recorded_at=datetime.now(timezone.utc).isoformat(),
    )


@router.get("/schema-diff", response_model=list[SchemaDiffRow])
async def schema_diff(
    _: UserInfo = Depends(get_current_user),
) -> list[SchemaDiffRow]:
    """오브젝트 종류별 Source ↔ Target 수 비교."""
    results: list[SchemaDiffRow] = []

    tasks_src = [_fetch_object_count(execute_query_src, sql) for sql in _OBJECT_TYPE_MAP.values()]
    tasks_tgt = [_fetch_object_count(execute_query_tgt, sql) for sql in _OBJECT_TYPE_MAP.values()]

    src_counts, tgt_counts = await asyncio.gather(
        asyncio.gather(*tasks_src),
        asyncio.gather(*tasks_tgt),
    )

    for i, obj_type in enumerate(_OBJECT_TYPE_MAP.keys()):
        src = src_counts[i]
        tgt = tgt_counts[i]
        diff = (src - tgt) if (src is not None and tgt is not None) else None
        results.append(SchemaDiffRow(
            object_type=obj_type,
            source_count=src,
            target_count=tgt,
            diff=diff,
        ))

    return results
