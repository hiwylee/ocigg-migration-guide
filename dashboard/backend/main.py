from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from core.env_loader import settings
from core.db import init_db
from core.scheduler import start_scheduler, stop_scheduler, setup_jobs
from api import auth, config, events, scripts, runbook, database
from api import goldengate
from api import validation
from api import alerts, cutover, users
from api.validation import seed_validation_data


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db(settings.ADMIN_USERNAME, settings.ADMIN_PASSWORD)
    await seed_validation_data()
    setup_jobs()
    start_scheduler()
    yield
    stop_scheduler()


app = FastAPI(
    title="Migration Dashboard API",
    description="AWS RDS Oracle SE → OCI DBCS Oracle SE 마이그레이션 대시보드",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.CORS_ORIGIN],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router,        prefix="/api/auth",   tags=["auth"])
app.include_router(config.router,      prefix="/api/config", tags=["config"])
app.include_router(events.router,      prefix="/api/events", tags=["events"])
app.include_router(goldengate.router,  prefix="/api/gg",     tags=["goldengate"])
app.include_router(scripts.router,    prefix="/api/scripts", tags=["scripts"])
app.include_router(runbook.router,    prefix="/api/runbook", tags=["runbook"])
app.include_router(database.router,  prefix="/api/db",      tags=["database"])
app.include_router(validation.router, prefix="/api/validation", tags=["validation"])
app.include_router(alerts.router,    prefix="/api/alerts",     tags=["alerts"])
app.include_router(cutover.router,   prefix="/api/cutover",    tags=["cutover"])
app.include_router(users.router,     prefix="/api/users",      tags=["users"])


@app.get("/health", tags=["system"])
async def health():
    return {"status": "ok", "version": "1.0.0"}
