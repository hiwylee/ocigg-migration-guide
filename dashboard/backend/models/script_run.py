from pydantic import BaseModel
from typing import Optional


class ScriptRunOut(BaseModel):
    id: int
    script_path: str
    risk_level: str
    started_at: str
    finished_at: Optional[str] = None
    status: str
    exit_code: Optional[int] = None
    log_path: Optional[str] = None
    run_by: Optional[str] = None
    reason: Optional[str] = None
