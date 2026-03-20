import asyncio
import hashlib
import os
import signal
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect

from api.auth import UserInfo, get_current_user
from core.db import get_db

router = APIRouter()

# ---------------------------------------------------------------------------
# 설정
# ---------------------------------------------------------------------------

SCRIPTS_DIR: str = os.getenv("SCRIPTS_DIR", "/app/scripts")

SCRIPT_METADATA: Dict[str, Dict] = {
    "01_pre_migration/step04_network_test.sh":    {"phase": 0, "risk": "LOW",      "role": "src_dba"},
    "01_pre_migration/step01_env_check.sh":       {"phase": 0, "risk": "LOW",      "role": "src_dba"},
    "01_pre_migration/step05_rds_param_check.sh": {"phase": 1, "risk": "LOW",      "role": "src_dba"},
    "01_pre_migration/step09_suplog_enable.sh":   {"phase": 1, "risk": "HIGH",     "role": "src_dba"},
    "01_pre_migration/step16_metadata_export.sh": {"phase": 1, "risk": "MEDIUM",   "role": "src_dba"},
    "01_pre_migration/step17_metadata_import.sh": {"phase": 2, "risk": "MEDIUM",   "role": "tgt_dba"},
    "02_migration/step01_gg_extract_create.sh":   {"phase": 3, "risk": "HIGH",     "role": "gg_operator"},
    "02_migration/step02_gg_pump_create.sh":      {"phase": 3, "risk": "HIGH",     "role": "gg_operator"},
    "02_migration/step03_gg_replicat_create.sh":  {"phase": 3, "risk": "HIGH",     "role": "gg_operator"},
    "02_migration/step17_gg_status_check.sh":     {"phase": 5, "risk": "LOW",      "role": "gg_operator"},
    "02_migration/step18_lag_monitoring.sh":      {"phase": 5, "risk": "LOW",      "role": "gg_operator"},
    "03_validation/step01_gg_process_check.sh":   {"phase": 6, "risk": "LOW",      "role": "gg_operator"},
    "03_validation/step10_cutover_execute.sh":    {"phase": 7, "risk": "CRITICAL", "role": "migration_leader"},
    "03_validation/step12_stabilization.sh":      {"phase": 8, "risk": "MEDIUM",   "role": "tgt_dba"},
}

# 동시 실행 방지를 위한 실행 중 상태 추적 (script_path → pid)
_running: Dict[str, int] = {}


# ---------------------------------------------------------------------------
# 유틸 함수
# ---------------------------------------------------------------------------

def _script_id(path: str) -> str:
    """스크립트 경로의 SHA256 앞 8자리를 script_id로 사용."""
    return hashlib.sha256(path.encode()).hexdigest()[:8]


def _id_to_path(script_id: str) -> Optional[str]:
    """script_id → 실제 경로 역매핑."""
    for path in SCRIPT_METADATA:
        if _script_id(path) == script_id:
            return path
    return None


def _is_safe_path(script_path: str) -> bool:
    """SCRIPTS_DIR 외부 경로 접근 방지."""
    abs_scripts = str(Path(SCRIPTS_DIR).resolve())
    full_path = str(Path(SCRIPTS_DIR, script_path).resolve())
    return full_path.startswith(abs_scripts + os.sep)


def _build_script_list(
    phase: Optional[int] = None,
    role: Optional[str] = None,
    risk: Optional[str] = None,
    last_runs: Optional[Dict[str, dict]] = None,
) -> List[dict]:
    result = []
    for path, meta in SCRIPT_METADATA.items():
        if phase is not None and meta["phase"] != phase:
            continue
        if role and meta["role"] != role:
            continue
        if risk and meta["risk"] != risk:
            continue

        full_path = Path(SCRIPTS_DIR, path)
        available = full_path.exists() and full_path.is_file()
        sid = _script_id(path)
        last_run = (last_runs or {}).get(path)

        result.append({
            "id": sid,
            "path": path,
            "phase": meta["phase"],
            "risk_level": meta["risk"],
            "role": meta["role"],
            "available": available,
            "last_run": last_run,
        })
    return result


async def _get_last_runs(db: aiosqlite.Connection) -> Dict[str, dict]:
    """각 스크립트 경로별 마지막 실행 결과 조회."""
    rows = await (
        await db.execute(
            """
            SELECT script_path, status, finished_at
            FROM script_runs
            WHERE id IN (
                SELECT MAX(id) FROM script_runs GROUP BY script_path
            )
            """
        )
    ).fetchall()
    return {
        r["script_path"]: {"status": r["status"], "finished_at": r["finished_at"]}
        for r in rows
    }


async def _log_event(
    db: aiosqlite.Connection,
    event_type: str,
    message: str,
    script_path: str,
    actor: str,
) -> None:
    now = datetime.utcnow().isoformat()
    await db.execute(
        "INSERT INTO event_log (event_type, message, related_script, actor, created_at) "
        "VALUES (?,?,?,?,?)",
        (event_type, message, script_path, actor, now),
    )
    await db.commit()


# ---------------------------------------------------------------------------
# WebSocket용 JWT 검증 헬퍼 (Depends 미사용)
# ---------------------------------------------------------------------------

async def _ws_get_user(websocket: WebSocket, db: aiosqlite.Connection) -> Optional[UserInfo]:
    """WebSocket 연결에서 Authorization 헤더 또는 token 쿼리 파라미터로 사용자 확인."""
    from jose import JWTError, jwt
    from core.env_loader import settings

    token: Optional[str] = None

    # 1) Authorization: Bearer <token>
    auth_header = websocket.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]

    # 2) ?token=<token> 쿼리 파라미터
    if not token:
        token = websocket.query_params.get("token")

    if not token:
        return None

    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        username: Optional[str] = payload.get("sub")
        if not username:
            return None
    except JWTError:
        return None

    row = await (
        await db.execute(
            "SELECT username, role FROM users WHERE username=?", (username,)
        )
    ).fetchone()
    if not row:
        return None
    return UserInfo(username=row["username"], role=row["role"])


# ---------------------------------------------------------------------------
# 엔드포인트
# ---------------------------------------------------------------------------

@router.get("")
async def list_scripts(
    phase: Optional[int] = Query(None),
    role: Optional[str] = Query(None),
    risk: Optional[str] = Query(None),
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
):
    last_runs = await _get_last_runs(db)
    return _build_script_list(phase=phase, role=role, risk=risk, last_runs=last_runs)


@router.get("/{script_id}")
async def get_script(
    script_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
):
    path = _id_to_path(script_id)
    if not path:
        raise HTTPException(status_code=404, detail="스크립트를 찾을 수 없습니다")

    meta = SCRIPT_METADATA[path]
    full_path = Path(SCRIPTS_DIR, path)
    available = full_path.exists() and full_path.is_file()

    # 마지막 실행 결과
    row = await (
        await db.execute(
            "SELECT * FROM script_runs WHERE script_path=? ORDER BY id DESC LIMIT 1",
            (path,),
        )
    ).fetchone()
    last_run = dict(row) if row else None

    return {
        "id": script_id,
        "path": path,
        "phase": meta["phase"],
        "risk_level": meta["risk"],
        "role": meta["role"],
        "available": available,
        "last_run": last_run,
    }


@router.get("/{script_id}/history")
async def script_history(
    script_id: str,
    limit: int = Query(20, le=100),
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
):
    path = _id_to_path(script_id)
    if not path:
        raise HTTPException(status_code=404, detail="스크립트를 찾을 수 없습니다")

    rows = await (
        await db.execute(
            "SELECT * FROM script_runs WHERE script_path=? ORDER BY id DESC LIMIT ?",
            (path, limit),
        )
    ).fetchall()
    return [dict(r) for r in rows]


@router.post("/{script_id}/kill")
async def kill_script(
    script_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    path = _id_to_path(script_id)
    if not path:
        raise HTTPException(status_code=404, detail="스크립트를 찾을 수 없습니다")

    pid = _running.get(path)
    if pid is None:
        raise HTTPException(status_code=409, detail="실행 중인 스크립트가 없습니다")

    try:
        os.killpg(os.getpgid(pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError) as e:
        raise HTTPException(status_code=500, detail=f"프로세스 종료 실패: {e}")

    now = datetime.utcnow().isoformat()
    await db.execute(
        "UPDATE script_runs SET status='killed', finished_at=? "
        "WHERE script_path=? AND status='running'",
        (now, path),
    )
    await db.commit()

    _running.pop(path, None)
    return {"status": "killed", "path": path}


@router.websocket("/{script_id}/run")
async def run_script_ws(
    script_id: str,
    websocket: WebSocket,
):
    await websocket.accept()

    # DB 연결 (get_db는 generator이므로 직접 열기)
    from core.db import get_db_path
    async with aiosqlite.connect(get_db_path()) as db:
        db.row_factory = aiosqlite.Row

        # ---- 1) 인증 ----
        user = await _ws_get_user(websocket, db)
        if not user:
            await websocket.send_text("[SYSTEM] 인증 실패: 유효한 토큰이 필요합니다")
            await websocket.close(code=4001)
            return

        # ---- 2) 스크립트 존재 확인 ----
        path = _id_to_path(script_id)
        if not path:
            await websocket.send_text("[SYSTEM] 오류: 스크립트를 찾을 수 없습니다")
            await websocket.close(code=4004)
            return

        meta = SCRIPT_METADATA[path]
        risk = meta["risk"]

        # ---- 3) 동시 실행 방지 ----
        if path in _running:
            await websocket.send_text(f"[SYSTEM] 오류: 이미 실행 중입니다 (PID={_running[path]})")
            await websocket.close(code=4009)
            return

        # ---- 4) 클라이언트 페이로드 수신 ----
        try:
            raw = await asyncio.wait_for(websocket.receive_text(), timeout=10.0)
            import json
            payload: dict = json.loads(raw)
        except (asyncio.TimeoutError, Exception):
            payload = {}

        reason: str = payload.get("reason", "").strip()
        confirm_token: str = payload.get("confirm_token", "").strip()

        # ---- 5) CRITICAL 확인 코드 검증 ----
        if risk == "CRITICAL":
            # config_registry에서 CUTOVER_CONFIRM_TOKEN 조회
            row = await (
                await db.execute(
                    "SELECT value FROM config_registry WHERE key='CUTOVER_CONFIRM_TOKEN'",
                )
            ).fetchone()
            expected_token = row["value"].strip() if row and row["value"] else ""

            # 헤더에서도 확인
            header_token = websocket.headers.get("x-confirm-token", "").strip()
            actual_token = confirm_token or header_token

            if not expected_token:
                await websocket.send_text("[SYSTEM] 오류: CUTOVER_CONFIRM_TOKEN이 설정되지 않았습니다")
                await websocket.close(code=4003)
                return
            if actual_token != expected_token:
                await websocket.send_text("[SYSTEM] 오류: Cut-over 승인 코드가 올바르지 않습니다")
                await websocket.close(code=4003)
                return

        # ---- 6) HIGH 이상: reason 필수 ----
        if risk in ("HIGH", "CRITICAL") and not reason:
            await websocket.send_text("[SYSTEM] 오류: risk가 HIGH 이상인 스크립트는 실행 사유(reason)가 필수입니다")
            await websocket.close(code=4003)
            return

        # ---- 7) 파일 존재 및 경로 안전 검증 ----
        if not _is_safe_path(path):
            await websocket.send_text("[SYSTEM] 오류: 허용되지 않은 경로입니다")
            await websocket.close(code=4003)
            return

        full_script_path = str(Path(SCRIPTS_DIR, path).resolve())
        if not Path(full_script_path).exists():
            await websocket.send_text(f"[SYSTEM] 오류: 스크립트 파일을 찾을 수 없습니다: {path}")
            await websocket.close(code=4004)
            return

        # ---- 8) script_runs에 실행 시작 기록 ----
        now = datetime.utcnow().isoformat()
        cur = await db.execute(
            "INSERT INTO script_runs (script_path, risk_level, started_at, status, run_by, reason) "
            "VALUES (?,?,?,?,?,?)",
            (path, risk, now, "running", user.username, reason or None),
        )
        await db.commit()
        run_id = cur.lastrowid

        # event_log: SCRIPT_START
        await _log_event(db, "SCRIPT_START", f"스크립트 실행 시작: {path}", path, user.username)

        # ---- 9) subprocess 실행 ----
        env = os.environ.copy()
        proc: Optional[subprocess.Popen] = None
        exit_code: Optional[int] = None

        try:
            proc = subprocess.Popen(
                ["bash", full_script_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                start_new_session=True,  # os.getpgid 가능하게
                text=True,
                bufsize=1,
            )
            _running[path] = proc.pid
            await websocket.send_text(f"[SYSTEM] 실행 시작 (PID={proc.pid}): {path}")

            # stdout/stderr 비동기 스트리밍
            loop = asyncio.get_event_loop()

            async def _stream_fd(pipe, prefix: str):
                while True:
                    line = await loop.run_in_executor(None, pipe.readline)
                    if not line:
                        break
                    try:
                        await websocket.send_text(f"{prefix}{line.rstrip()}")
                    except Exception:
                        break

            await asyncio.gather(
                _stream_fd(proc.stdout, "[STDOUT] "),
                _stream_fd(proc.stderr, "[STDERR] "),
            )

            exit_code = await loop.run_in_executor(None, proc.wait)

        except WebSocketDisconnect:
            # 클라이언트가 끊어진 경우 프로세스도 종료
            if proc and proc.poll() is None:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                except Exception:
                    pass
            exit_code = -1
        except Exception as e:
            try:
                await websocket.send_text(f"[SYSTEM] 실행 오류: {e}")
            except Exception:
                pass
            exit_code = -1
        finally:
            _running.pop(path, None)

        # ---- 10) 실행 결과 기록 ----
        finished = datetime.utcnow().isoformat()
        if exit_code is None:
            status = "killed"
        elif exit_code == 0:
            status = "success"
        else:
            status = "failed"

        # killed 상태는 kill 엔드포인트에서 이미 업데이트했을 수 있음
        row_check = await (
            await db.execute("SELECT status FROM script_runs WHERE id=?", (run_id,))
        ).fetchone()
        if row_check and row_check["status"] == "running":
            await db.execute(
                "UPDATE script_runs SET finished_at=?, status=?, exit_code=? WHERE id=?",
                (finished, status, exit_code, run_id),
            )
            await db.commit()

        # event_log: SCRIPT_COMPLETE / SCRIPT_FAIL
        if status == "success":
            event_type = "SCRIPT_COMPLETE"
            msg = f"스크립트 완료 (exit_code=0): {path}"
        elif status == "killed":
            event_type = "SCRIPT_FAIL"
            msg = f"스크립트 강제 종료: {path}"
        else:
            event_type = "SCRIPT_FAIL"
            msg = f"스크립트 실패 (exit_code={exit_code}): {path}"

        await _log_event(db, event_type, msg, path, user.username)

        # 완료 메시지 전송
        try:
            await websocket.send_text(
                f"[SYSTEM] 실행 완료 | status={status} | exit_code={exit_code}"
            )
            await websocket.close()
        except Exception:
            pass
