from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from datetime import datetime
import aiosqlite
from pydantic import BaseModel

from core.db import get_db, pwd_context
from api.auth import get_current_user, UserInfo

router = APIRouter()

VALID_ROLES = {"admin", "migration_leader", "src_dba", "tgt_dba", "gg_operator", "viewer"}


class UserOut(BaseModel):
    username: str
    role: str
    last_login: Optional[str] = None


class UserCreate(BaseModel):
    username: str
    password: str
    role: str = "viewer"


class RoleUpdate(BaseModel):
    role: str


class PasswordReset(BaseModel):
    new_password: str


@router.get("", response_model=List[UserOut])
async def list_users(
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if current_user.role not in ("admin", "migration_leader"):
        raise HTTPException(status_code=403, detail="권한이 없습니다")
    rows = await (
        await db.execute("SELECT username, role, last_login FROM users ORDER BY username")
    ).fetchall()
    return [UserOut(**dict(r)) for r in rows]


@router.post("", response_model=UserOut, status_code=201)
async def create_user(
    body: UserCreate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="admin 권한 필요")
    if body.role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail=f"유효하지 않은 역할: {body.role}")
    existing = await (
        await db.execute("SELECT id FROM users WHERE username=?", (body.username,))
    ).fetchone()
    if existing:
        raise HTTPException(status_code=409, detail=f"사용자 '{body.username}'이 이미 존재합니다")
    hashed = pwd_context.hash(body.password)
    await db.execute(
        "INSERT INTO users (username, hashed_password, role) VALUES (?,?,?)",
        (body.username, hashed, body.role),
    )
    await db.commit()
    return UserOut(username=body.username, role=body.role, last_login=None)


@router.put("/{username}/role", response_model=UserOut)
async def update_role(
    username: str,
    body: RoleUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="admin 권한 필요")
    if body.role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail=f"유효하지 않은 역할: {body.role}")
    row = await (
        await db.execute("SELECT username, last_login FROM users WHERE username=?", (username,))
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"사용자 '{username}'을 찾을 수 없습니다")
    await db.execute("UPDATE users SET role=? WHERE username=?", (body.role, username))
    await db.commit()
    return UserOut(username=username, role=body.role, last_login=row["last_login"])


@router.put("/{username}/password")
async def reset_password(
    username: str,
    body: PasswordReset,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if current_user.role != "admin" and current_user.username != username:
        raise HTTPException(status_code=403, detail="권한이 없습니다")
    row = await (
        await db.execute("SELECT id FROM users WHERE username=?", (username,))
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"사용자 '{username}'을 찾을 수 없습니다")
    hashed = pwd_context.hash(body.new_password)
    await db.execute("UPDATE users SET hashed_password=? WHERE username=?", (hashed, username))
    await db.commit()
    return {"status": "updated", "username": username}


@router.delete("/{username}")
async def delete_user(
    username: str,
    db: aiosqlite.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="admin 권한 필요")
    if username == current_user.username:
        raise HTTPException(status_code=400, detail="자기 자신은 삭제할 수 없습니다")
    row = await (
        await db.execute("SELECT id FROM users WHERE username=?", (username,))
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"사용자 '{username}'을 찾을 수 없습니다")
    await db.execute("DELETE FROM users WHERE username=?", (username,))
    await db.commit()
    return {"status": "deleted", "username": username}
