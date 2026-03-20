from pydantic import BaseModel
from typing import Optional


class ValidationItem(BaseModel):
    id: int
    domain: str
    item_no: int
    item_name: str
    priority: str
    status: str
    note: Optional[str] = None
    assignee: Optional[str] = None
    verified_at: Optional[str] = None
    verified_by: Optional[str] = None


class ValidationUpdate(BaseModel):
    status: Optional[str] = None
    note: Optional[str] = None
    assignee: Optional[str] = None


class ValidationSummary(BaseModel):
    total: int
    pass_count: int
    warn_count: int
    fail_count: int
    pending_count: int
    go_nogo: str  # GO | CONDITIONAL_GO | NO_GO | PENDING
