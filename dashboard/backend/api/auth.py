from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Optional
import aiosqlite

from core.env_loader import settings
from core.db import get_db

router = APIRouter()

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


class Token(BaseModel):
    access_token: str
    token_type: str
    username: str
    role: str


class UserInfo(BaseModel):
    username: str
    role: str


def create_access_token(username: str, role: str) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return jwt.encode(
        {"sub": username, "role": role, "exp": expire},
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: aiosqlite.Connection = Depends(get_db),
) -> UserInfo:
    exc = HTTPException(status_code=401, detail="인증 정보가 유효하지 않습니다")
    try:
        payload = jwt.decode(
            token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM]
        )
        username: Optional[str] = payload.get("sub")
        if not username:
            raise exc
    except JWTError:
        raise exc

    row = await (
        await db.execute(
            "SELECT username, role FROM users WHERE username=?", (username,)
        )
    ).fetchone()
    if not row:
        raise exc
    return UserInfo(username=row["username"], role=row["role"])


@router.post("/login", response_model=Token)
async def login(
    form: OAuth2PasswordRequestForm = Depends(),
    db: aiosqlite.Connection = Depends(get_db),
):
    row = await (
        await db.execute(
            "SELECT username, hashed_password, role FROM users WHERE username=?",
            (form.username,),
        )
    ).fetchone()
    if not row or not pwd_context.verify(form.password, row["hashed_password"]):
        raise HTTPException(status_code=401, detail="사용자명 또는 비밀번호가 올바르지 않습니다")

    now = datetime.utcnow().isoformat()
    await db.execute(
        "UPDATE users SET last_login=? WHERE username=?", (now, form.username)
    )
    await db.commit()

    token = create_access_token(row["username"], row["role"])
    return Token(
        access_token=token,
        token_type="bearer",
        username=row["username"],
        role=row["role"],
    )


@router.get("/me", response_model=UserInfo)
async def me(current_user: UserInfo = Depends(get_current_user)):
    return current_user
