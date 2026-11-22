import os

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    service_path = os.getenv("SERVICE_PATH", "/ops")
    RUNTIME_PREFIX = os.getenv("RUNTIME_PREFIX")
    API_V1_STR: str = "/api/v1"


settings = Settings()
