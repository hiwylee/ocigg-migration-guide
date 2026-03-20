from pydantic import BaseModel
from typing import Optional


class ConfigEntry(BaseModel):
    key: str
    value: Optional[str] = None
    locked: bool = False
    changed_by: Optional[str] = None
    changed_at: Optional[str] = None


class ConfigUpdate(BaseModel):
    value: str
