from pydantic import BaseModel
from typing import Optional


class EventCreate(BaseModel):
    event_type: str
    message: str
    related_script: Optional[str] = None
    related_item: Optional[str] = None


class EventOut(BaseModel):
    id: int
    event_type: str
    message: str
    related_script: Optional[str] = None
    related_item: Optional[str] = None
    actor: Optional[str] = None
    created_at: str
    confirmed_by: Optional[str] = None
    confirmed_at: Optional[str] = None
