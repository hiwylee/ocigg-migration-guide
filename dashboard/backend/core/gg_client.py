"""
OCI GoldenGate Admin Server REST API v2 클라이언트
"""
from __future__ import annotations

import os
from typing import Any, Optional

import httpx

from core.env_loader import settings


class NotConfiguredError(Exception):
    """GG_ADMIN_URL이 설정되지 않은 경우"""


class GGClientError(Exception):
    """GoldenGate REST API 호출 실패"""


def _get_verify() -> Any:
    """TLS 검증 설정 반환: CA 번들 파일이 존재하면 경로, 없으면 True (시스템 CA)"""
    ca_bundle = settings.GG_CA_BUNDLE
    if ca_bundle and os.path.isfile(ca_bundle):
        return ca_bundle
    return True


def _get_client() -> httpx.AsyncClient:
    if not settings.GG_ADMIN_URL:
        raise NotConfiguredError("GG_ADMIN_URL이 설정되지 않았습니다")
    base_url = settings.GG_ADMIN_URL.rstrip("/")
    auth = (settings.GG_ADMIN_USER, settings.GG_ADMIN_PASS)
    verify = _get_verify()
    return httpx.AsyncClient(
        base_url=base_url,
        auth=auth,
        verify=verify,
        timeout=15.0,
        headers={"Accept": "application/json", "Content-Type": "application/json"},
    )


def _parse_status(raw: str | None) -> str:
    """GG REST API 상태 문자열을 RUNNING/STOPPED/ABEND/UNKNOWN 중 하나로 정규화"""
    if not raw:
        return "UNKNOWN"
    upper = raw.upper()
    if "RUNNING" in upper:
        return "RUNNING"
    if "STOPPED" in upper or "STOP" in upper:
        return "STOPPED"
    if "ABEND" in upper or "ABENDED" in upper:
        return "ABEND"
    return "UNKNOWN"


def _lag_to_seconds(lag_str: str | None) -> Optional[float]:
    """
    GG REST API의 lag 표현 (예: "00:00:05", "5" 등) 을 float 초로 변환.
    파싱 불가하면 None 반환.
    """
    if lag_str is None:
        return None
    lag_str = str(lag_str).strip()
    if lag_str in ("", "N/A", "null", "None"):
        return None
    # HH:MM:SS 형식
    if ":" in lag_str:
        parts = lag_str.split(":")
        try:
            if len(parts) == 3:
                h, m, s = parts
                return int(h) * 3600 + int(m) * 60 + float(s)
            if len(parts) == 2:
                m, s = parts
                return int(m) * 60 + float(s)
        except (ValueError, TypeError):
            return None
    # 순수 숫자 (초)
    try:
        return float(lag_str)
    except (ValueError, TypeError):
        return None


async def get_deployments() -> list[dict]:
    """배포 목록 조회"""
    try:
        async with _get_client() as client:
            resp = await client.get("/services/v2/deployments")
            resp.raise_for_status()
            data = resp.json()
            return data.get("items", data if isinstance(data, list) else [])
    except NotConfiguredError:
        raise
    except httpx.HTTPStatusError as exc:
        raise GGClientError(f"HTTP {exc.response.status_code}: {exc.response.text}") from exc
    except Exception as exc:
        raise GGClientError(str(exc)) from exc


async def get_process_status(process_name: str) -> dict:
    """
    단일 프로세스 상태 조회
    반환: {"name": str, "status": RUNNING|STOPPED|ABEND|UNKNOWN, "lag_seconds": float|None}
    """
    try:
        async with _get_client() as client:
            # Extract / Replicat 공통 엔드포인트 시도
            for path in (
                f"/services/v2/extracts/{process_name}",
                f"/services/v2/replicats/{process_name}",
            ):
                try:
                    resp = await client.get(path)
                    if resp.status_code == 404:
                        continue
                    resp.raise_for_status()
                    data = resp.json()
                    item = data.get("items", [data])[0] if isinstance(data, dict) else data[0]
                    raw_status = (
                        item.get("status")
                        or item.get("extractStatus")
                        or item.get("replicatStatus")
                        or item.get("processStatus")
                    )
                    lag_raw = (
                        item.get("lagAtChkpt")
                        or item.get("lag")
                        or item.get("lagAtCheckpoint")
                        or item.get("inputCheckpointLag")
                    )
                    return {
                        "name": process_name,
                        "status": _parse_status(raw_status),
                        "lag_seconds": _lag_to_seconds(str(lag_raw) if lag_raw is not None else None),
                    }
                except httpx.HTTPStatusError:
                    continue
        # 둘 다 404면 UNKNOWN
        return {"name": process_name, "status": "UNKNOWN", "lag_seconds": None}
    except NotConfiguredError:
        raise
    except GGClientError:
        raise
    except Exception as exc:
        raise GGClientError(str(exc)) from exc


async def get_all_processes() -> list[dict]:
    """EXT1 / PUMP1 / REP1 상태를 한 번에 조회"""
    names = [settings.GG_EXTRACT_NAME, settings.GG_PUMP_NAME, settings.GG_REPLICAT_NAME]
    results = []
    for name in names:
        try:
            results.append(await get_process_status(name))
        except GGClientError as exc:
            results.append({"name": name, "status": "UNKNOWN", "lag_seconds": None, "error": str(exc)})
    return results


async def _send_action(process_name: str, action: str) -> dict:
    """
    Extract / Replicat 에 액션(start/stop/kill) 전송.
    action: "START" | "STOP" | "KILL"
    """
    try:
        async with _get_client() as client:
            for path_tpl in (
                "/services/v2/extracts/{name}",
                "/services/v2/replicats/{name}",
            ):
                path = path_tpl.format(name=process_name)
                try:
                    # 확인
                    check = await client.get(path)
                    if check.status_code == 404:
                        continue
                    resp = await client.patch(
                        path,
                        json={"action": action},
                    )
                    resp.raise_for_status()
                    return {"result": "OK", "action": action, "process": process_name}
                except httpx.HTTPStatusError as exc:
                    if exc.response.status_code == 404:
                        continue
                    raise GGClientError(
                        f"HTTP {exc.response.status_code}: {exc.response.text}"
                    ) from exc
        return {"result": "NOT_FOUND", "process": process_name}
    except (NotConfiguredError, GGClientError):
        raise
    except Exception as exc:
        raise GGClientError(str(exc)) from exc


async def start_process(process_name: str) -> dict:
    return await _send_action(process_name, "START")


async def stop_process(process_name: str) -> dict:
    return await _send_action(process_name, "STOP")


async def kill_process(process_name: str) -> dict:
    return await _send_action(process_name, "KILL")


async def get_lag(process_name: str) -> Optional[float]:
    """프로세스 LAG를 초 단위 float으로 반환. 조회 불가 시 None."""
    try:
        info = await get_process_status(process_name)
        return info.get("lag_seconds")
    except (NotConfiguredError, GGClientError):
        return None


async def get_discard_count(replicat_name: str) -> int:
    """Replicat의 discard 레코드 수 조회"""
    try:
        async with _get_client() as client:
            resp = await client.get(f"/services/v2/replicats/{replicat_name}/discards")
            resp.raise_for_status()
            data = resp.json()
            # API 응답 구조에 따라 count 또는 items 길이 반환
            if isinstance(data, dict):
                return data.get("count", len(data.get("items", [])))
            if isinstance(data, list):
                return len(data)
            return 0
    except NotConfiguredError:
        raise
    except Exception as exc:
        raise GGClientError(str(exc)) from exc


async def get_error_log(lines: int = 50) -> list[str]:
    """GG 에러 로그 마지막 N줄 반환"""
    try:
        async with _get_client() as client:
            resp = await client.get(
                "/services/v2/diagnostics/messages",
                params={"limit": lines, "severity": "ERROR"},
            )
            resp.raise_for_status()
            data = resp.json()
            items = data.get("items", data if isinstance(data, list) else [])
            log_lines: list[str] = []
            for item in items:
                ts = item.get("timestamp", "")
                severity = item.get("severity", "")
                msg = item.get("message", str(item))
                log_lines.append(f"[{ts}] [{severity}] {msg}")
            return log_lines[-lines:]
    except NotConfiguredError:
        raise
    except Exception as exc:
        raise GGClientError(str(exc)) from exc
