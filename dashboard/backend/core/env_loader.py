from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    # Source DB (AWS RDS Oracle SE)
    SRC_DB_HOST: str = ""
    SRC_DB_PORT: int = 1521
    SRC_DB_SID: str = ""
    SRC_DB_SERVICE: str = ""
    SRC_DBA_USER: str = "admin"
    SRC_DBA_PASS: str = ""
    SRC_GG_USER: str = "GGADMIN"
    SRC_GG_PASS: str = ""
    SRC_MIG_USER: str = "MIGRATION_USER"
    SRC_MIG_PASS: str = ""

    # Target DB (OCI DBCS Oracle SE)
    TGT_DB_HOST: str = ""
    TGT_DB_PORT: int = 1521
    TGT_DB_SID: str = ""
    TGT_DB_SERVICE: str = ""
    TGT_DBA_USER: str = "SYS"
    TGT_DBA_PASS: str = ""
    TGT_GG_USER: str = "GGADMIN"
    TGT_GG_PASS: str = ""
    TGT_MIG_USER: str = "MIGRATION_USER"
    TGT_MIG_PASS: str = ""

    # OCI GoldenGate
    GG_ADMIN_URL: str = ""
    GG_ADMIN_USER: str = "oggadmin"
    GG_ADMIN_PASS: str = ""
    GG_DEPLOYMENT_NAME: str = ""
    GG_EXTRACT_NAME: str = "EXT1"
    GG_PUMP_NAME: str = "PUMP1"
    GG_REPLICAT_NAME: str = "REP1"
    GG_CA_BUNDLE: str = "/app/certs/ca-bundle.crt"

    # OCI Object Storage
    OCI_NAMESPACE: str = ""
    OCI_BUCKET: str = ""
    OCI_REGION: str = "ap-tokyo-1"

    # Migration
    MIGRATION_SCHEMAS: str = ""

    # JWT
    JWT_SECRET_KEY: str = "change-me"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 480

    # Admin (초기 기동 시 자동 생성)
    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str = "change-me"

    # App
    CORS_ORIGIN: str = "http://localhost:3000"
    LAG_WARNING_SECONDS: int = 15
    LAG_CRITICAL_SECONDS: int = 30
    DB_PATH: str = "/app/db/dashboard.db"


settings = Settings()
