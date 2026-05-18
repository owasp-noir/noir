# Regression for fastapi-template / full-stack-fastapi-template:
# `prefix=settings.API_V1_STR` is an attribute reference, not a string
# literal. The previous configure_router_prefix logic kept the raw
# expression and emitted garbage URLs like `/settings.API_V1_STR/...`.
from fastapi import FastAPI

from app.api.main import api_router
from app.core.config import settings

app = FastAPI()
app.include_router(api_router, prefix=settings.API_V1_STR)
