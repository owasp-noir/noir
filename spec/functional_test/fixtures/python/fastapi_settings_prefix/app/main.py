# Regression for fastapi-template / full-stack-fastapi-template:
# `prefix=settings.API_V1_STR` is an attribute reference, not a string
# literal. The previous configure_router_prefix logic kept the raw
# expression and emitted garbage URLs like `/settings.API_V1_STR/...`.
from fastapi import Depends, FastAPI

from app.api.routes import factory
from app.api.main import api_router
from app.core.config import settings
from app.core.factory import get_factory_settings

API_PREFIX = settings.API_V1_STR
factory_settings = get_factory_settings()

app = FastAPI()
app.include_router(
    router=api_router,
    prefix=API_PREFIX,
    dependencies=[Depends(lambda: True)],
)
app.include_router(factory.router, prefix=factory_settings.api_prefix)
