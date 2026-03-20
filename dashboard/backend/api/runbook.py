"""
Runbook Viewer API
마크다운 런북 파일 목록 조회, 본문 반환, Step 완료 관리.
"""
from __future__ import annotations

import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from api.auth import get_current_user, UserInfo
from core.db import get_db

router = APIRouter()

# 마크다운 파일 디렉터리 (환경변수로 override 가능)
PLAN_DIR = Path(os.getenv("PLAN_DIR", "/app/plan"))

# 파일명 → (title, phase) 메타 매핑
_FILE_META: dict[str, tuple[str, int | None]] = {
    "migration_plan.md":    ("마이그레이션 마스터 플랜",   None),
    "01.pre_migration.md":  ("Phase 0-2: 사전 준비",        0),
    "02.migration.md":      ("Phase 3-5: 마이그레이션 실행", 3),
    "02_migration.md":      ("Phase 3-5: 마이그레이션 실행", 3),
    "03.validation.md":     ("Phase 6-7: 검증 및 Cut-over",  6),
}


# ─── 유틸 함수 ───────────────────────────────────────────────────────────────

def _slugify(text: str) -> str:
    """헤더 텍스트를 URL-safe step_id로 변환."""
    slug = text.strip().lower()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"[\s_]+", "-", slug)
    slug = re.sub(r"-+", "-", slug)
    return slug.strip("-")


def _extract_steps(content: str) -> list[dict]:
    """## 헤더 기반으로 Step 목록을 추출."""
    steps: list[dict] = []
    seen_slugs: dict[str, int] = {}
    for i, line in enumerate(content.splitlines()):
        if line.startswith("## "):
            title = line[3:].strip()
            base_slug = _slugify(title)
            count = seen_slugs.get(base_slug, 0)
            seen_slugs[base_slug] = count + 1
            step_id = base_slug if count == 0 else f"{base_slug}-{count}"
            steps.append({
                "step_id": step_id,
                "title": title,
                "index": len(steps),
                "completed": False,
                "completed_by": None,
                "completed_at": None,
            })
    return steps


def _extract_warnings(content: str) -> list[str]:
    """WARNING / 주의 / ※ 포함 라인 추출."""
    warnings: list[str] = []
    pattern = re.compile(r"(warning|주의|※|caution|danger|⚠)", re.IGNORECASE)
    for line in content.splitlines():
        if pattern.search(line):
            cleaned = line.strip().lstrip("#").lstrip(">").strip()
            if cleaned:
                warnings.append(cleaned)
    return warnings


def _extract_sql_blocks(content: str, steps: list[dict]) -> list[dict]:
    """SQL/PL-SQL 코드블록 추출. step_id는 블록 이전의 마지막 ## 헤더로 결정."""
    results: list[dict] = []
    lines = content.splitlines()
    in_block = False
    block_lang = ""
    block_lines: list[str] = []
    current_step_id: str | None = None
    block_index = 0

    for line in lines:
        if line.startswith("## "):
            title = line[3:].strip()
            slug = _slugify(title)
            # steps 목록에서 일치하는 step_id 탐색
            for s in steps:
                if s["title"] == title or s["step_id"] == slug:
                    current_step_id = s["step_id"]
                    break
        if not in_block:
            m = re.match(r"^```(\w*)", line)
            if m:
                block_lang = m.group(1).lower()
                if block_lang in ("sql", "plsql", "oracle", ""):
                    in_block = True
                    block_lines = []
        else:
            if line.startswith("```"):
                sql_text = "\n".join(block_lines).strip()
                if sql_text:
                    results.append({
                        "index": block_index,
                        "sql": sql_text,
                        "step_id": current_step_id,
                    })
                    block_index += 1
                in_block = False
                block_lines = []
            else:
                block_lines.append(line)

    return results


def _get_md_path(filename: str) -> Path:
    """파일명 검증 후 절대 경로 반환."""
    if "/" in filename or "\\" in filename or not filename.endswith(".md"):
        raise HTTPException(status_code=400, detail="유효하지 않은 파일명입니다")
    path = PLAN_DIR / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"파일을 찾을 수 없습니다: {filename}")
    return path


# ─── 응답 모델 ────────────────────────────────────────────────────────────────

class RunbookFile(BaseModel):
    filename: str
    title: str
    phase: Optional[int]


class Step(BaseModel):
    step_id: str
    title: str
    index: int
    completed: bool
    completed_by: Optional[str]
    completed_at: Optional[str]


class CompleteRequest(BaseModel):
    completed_by: Optional[str] = None


class WarningItem(BaseModel):
    text: str


class SqlBlock(BaseModel):
    index: int
    sql: str
    step_id: Optional[str]


# ─── 엔드포인트 ───────────────────────────────────────────────────────────────

@router.get("/files", response_model=list[RunbookFile])
async def list_files(
    _: UserInfo = Depends(get_current_user),
) -> list[RunbookFile]:
    """plan/ 디렉터리의 .md 파일 목록 반환."""
    result: list[RunbookFile] = []
    if not PLAN_DIR.exists():
        return result

    for path in sorted(PLAN_DIR.glob("*.md")):
        fname = path.name
        meta = _FILE_META.get(fname, (fname, None))
        result.append(RunbookFile(filename=fname, title=meta[0], phase=meta[1]))

    return result


@router.get("/{filename}", response_model=str)
async def get_file_content(
    filename: str,
    _: UserInfo = Depends(get_current_user),
) -> str:
    """마크다운 파일 원문 텍스트 반환."""
    path = _get_md_path(filename)
    return path.read_text(encoding="utf-8")


@router.get("/{filename}/steps", response_model=list[Step])
async def list_steps(
    filename: str,
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
) -> list[Step]:
    """파일의 ## 헤더 기반 Step 목록 (완료 상태 포함)."""
    path = _get_md_path(filename)
    content = path.read_text(encoding="utf-8")
    steps = _extract_steps(content)

    # step_progress 테이블에서 완료 상태 조회
    rows = await (
        await db.execute(
            "SELECT step_id, completed, completed_by, completed_at "
            "FROM step_progress WHERE filename=?",
            (filename,),
        )
    ).fetchall()
    progress: dict[str, dict] = {
        row["step_id"]: {
            "completed": bool(row["completed"]),
            "completed_by": row["completed_by"],
            "completed_at": row["completed_at"],
        }
        for row in rows
    }

    for step in steps:
        p = progress.get(step["step_id"])
        if p:
            step["completed"] = p["completed"]
            step["completed_by"] = p["completed_by"]
            step["completed_at"] = p["completed_at"]

    return [Step(**s) for s in steps]


@router.post("/{filename}/steps/{step_id}/complete", response_model=Step)
async def complete_step(
    filename: str,
    step_id: str,
    body: CompleteRequest,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
) -> Step:
    """Step 완료 처리."""
    path = _get_md_path(filename)
    content = path.read_text(encoding="utf-8")
    steps = _extract_steps(content)

    step = next((s for s in steps if s["step_id"] == step_id), None)
    if step is None:
        raise HTTPException(status_code=404, detail=f"step_id를 찾을 수 없습니다: {step_id}")

    completed_by = body.completed_by or current_user.username
    completed_at = datetime.now(timezone.utc).isoformat()

    await db.execute(
        """INSERT INTO step_progress (filename, step_id, completed, completed_by, completed_at)
           VALUES (?, ?, 1, ?, ?)
           ON CONFLICT(filename, step_id)
           DO UPDATE SET completed=1, completed_by=excluded.completed_by,
                         completed_at=excluded.completed_at""",
        (filename, step_id, completed_by, completed_at),
    )
    await db.commit()

    step["completed"] = True
    step["completed_by"] = completed_by
    step["completed_at"] = completed_at
    return Step(**step)


@router.post("/{filename}/steps/{step_id}/undo", response_model=Step)
async def undo_step(
    filename: str,
    step_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _: UserInfo = Depends(get_current_user),
) -> Step:
    """Step 완료 취소."""
    path = _get_md_path(filename)
    content = path.read_text(encoding="utf-8")
    steps = _extract_steps(content)

    step = next((s for s in steps if s["step_id"] == step_id), None)
    if step is None:
        raise HTTPException(status_code=404, detail=f"step_id를 찾을 수 없습니다: {step_id}")

    await db.execute(
        """INSERT INTO step_progress (filename, step_id, completed, completed_by, completed_at)
           VALUES (?, ?, 0, NULL, NULL)
           ON CONFLICT(filename, step_id)
           DO UPDATE SET completed=0, completed_by=NULL, completed_at=NULL""",
        (filename, step_id),
    )
    await db.commit()

    step["completed"] = False
    return Step(**step)


@router.get("/{filename}/warnings", response_model=list[WarningItem])
async def get_warnings(
    filename: str,
    _: UserInfo = Depends(get_current_user),
) -> list[WarningItem]:
    """WARNING/주의/※ 포함 라인 추출."""
    path = _get_md_path(filename)
    content = path.read_text(encoding="utf-8")
    warnings = _extract_warnings(content)
    return [WarningItem(text=w) for w in warnings]


@router.get("/{filename}/sql-blocks", response_model=list[SqlBlock])
async def get_sql_blocks(
    filename: str,
    _: UserInfo = Depends(get_current_user),
) -> list[SqlBlock]:
    """SQL 코드블록 추출."""
    path = _get_md_path(filename)
    content = path.read_text(encoding="utf-8")
    steps = _extract_steps(content)
    blocks = _extract_sql_blocks(content, steps)
    return [SqlBlock(**b) for b in blocks]
