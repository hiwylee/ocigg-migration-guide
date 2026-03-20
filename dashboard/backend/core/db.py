import aiosqlite
import os
from pathlib import Path
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

_DB_PATH: str = os.getenv("DB_PATH", "/app/db/dashboard.db")


def get_db_path() -> str:
    return _DB_PATH


CREATE_TABLES_SQL = """
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS users (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    username        TEXT    UNIQUE NOT NULL,
    hashed_password TEXT    NOT NULL,
    role            TEXT    NOT NULL DEFAULT 'viewer',
    last_login      TEXT
);

CREATE TABLE IF NOT EXISTS phase_progress (
    phase_no        INTEGER PRIMARY KEY,
    phase_name      TEXT    NOT NULL,
    status          TEXT    NOT NULL DEFAULT 'pending',
    started_at      TEXT,
    completed_at    TEXT,
    completed_by    TEXT
);

CREATE TABLE IF NOT EXISTS config_registry (
    key             TEXT    PRIMARY KEY,
    value           TEXT,
    locked          INTEGER NOT NULL DEFAULT 0,
    changed_by      TEXT,
    changed_at      TEXT
);

CREATE TABLE IF NOT EXISTS validation_results (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    domain          TEXT    NOT NULL,
    item_no         INTEGER NOT NULL,
    item_name       TEXT    NOT NULL,
    priority        TEXT    NOT NULL DEFAULT 'MEDIUM',
    status          TEXT    NOT NULL DEFAULT 'PENDING',
    note            TEXT,
    assignee        TEXT,
    verified_at     TEXT,
    verified_by     TEXT,
    exec_output     TEXT
);

CREATE TABLE IF NOT EXISTS script_runs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    script_path     TEXT    NOT NULL,
    risk_level      TEXT    NOT NULL DEFAULT 'LOW',
    started_at      TEXT    NOT NULL,
    finished_at     TEXT,
    status          TEXT    NOT NULL DEFAULT 'running',
    exit_code       INTEGER,
    log_path        TEXT,
    run_by          TEXT,
    reason          TEXT
);

CREATE TABLE IF NOT EXISTS lag_history (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    process_name    TEXT    NOT NULL,
    lag_seconds     REAL,
    recorded_at     TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS event_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type      TEXT    NOT NULL,
    message         TEXT    NOT NULL,
    related_script  TEXT,
    related_item    TEXT,
    actor           TEXT,
    created_at      TEXT    NOT NULL,
    confirmed_by    TEXT,
    confirmed_at    TEXT
);

CREATE TABLE IF NOT EXISTS alerts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    level           TEXT    NOT NULL,
    message         TEXT    NOT NULL,
    confirmed_by    TEXT,
    confirmed_at    TEXT,
    created_at      TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS step_progress (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    filename     TEXT NOT NULL,
    step_id      TEXT NOT NULL,
    completed    INTEGER NOT NULL DEFAULT 0,
    completed_by TEXT,
    completed_at TEXT,
    UNIQUE(filename, step_id)
);
"""

PHASE_SEED = [
    (0, "적합성 & 환경 점검",             "pending"),
    (1, "소스 DB 준비 (AWS RDS)",         "pending"),
    (2, "타겟 DB 준비 (OCI DBCS)",        "pending"),
    (3, "OCI GoldenGate 구성",            "pending"),
    (4, "초기 데이터 적재 (expdp→impdp)", "pending"),
    (5, "델타 동기화",                     "pending"),
    (6, "검증 (136항목)",                  "pending"),
    (7, "Cut-over",                        "pending"),
    (8, "마이그레이션 후 안정화",           "pending"),
]

CONFIG_SEED = [
    ("GG_EXTRACT_NAME",         "EXT1"),
    ("GG_PUMP_NAME",            "PUMP1"),
    ("GG_REPLICAT_NAME",        "REP1"),
    ("LAG_WARNING_SECONDS",     "15"),
    ("LAG_CRITICAL_SECONDS",    "30"),
    ("CUTOVER_TIMEOUT_MINUTES", "30"),
    ("SOURCE_RDS_RETAIN_DAYS",  "14"),
    ("EXPDP_SCN",               ""),
    ("CURRENT_PHASE",           "0"),
    ("LAG_STABLE_SINCE",        ""),   # 24h 안정화 기산점
]


async def get_db():
    async with aiosqlite.connect(get_db_path()) as db:
        db.row_factory = aiosqlite.Row
        yield db


async def init_db(admin_username: str, admin_password: str) -> None:
    Path(get_db_path()).parent.mkdir(parents=True, exist_ok=True)
    async with aiosqlite.connect(get_db_path()) as db:
        db.row_factory = aiosqlite.Row
        await db.executescript(CREATE_TABLES_SQL)

        for phase_no, phase_name, status in PHASE_SEED:
            await db.execute(
                "INSERT OR IGNORE INTO phase_progress (phase_no, phase_name, status) VALUES (?,?,?)",
                (phase_no, phase_name, status),
            )

        for key, value in CONFIG_SEED:
            await db.execute(
                "INSERT OR IGNORE INTO config_registry (key, value) VALUES (?,?)",
                (key, value),
            )

        row = await (
            await db.execute("SELECT id FROM users WHERE username=?", (admin_username,))
        ).fetchone()
        if not row:
            hashed = pwd_context.hash(admin_password)
            await db.execute(
                "INSERT INTO users (username, hashed_password, role) VALUES (?,?,?)",
                (admin_username, hashed, "admin"),
            )

        await db.commit()
