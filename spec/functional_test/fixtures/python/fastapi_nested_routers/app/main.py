from fastapi import FastAPI

from app.api import router as api_router

app = FastAPI()

# Aliased router import: the included symbol is `router`, surfaced
# locally as `api_router`. Prefix configuration must translate the
# alias back to `router` when recursing into api.py.
app.include_router(api_router, prefix="/api")
