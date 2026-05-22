import http
from typing import FrozenSet, Optional

from fastapi import APIRouter, FastAPI, Path, Query
from fastapi.staticfiles import StaticFiles
from api import api
from api import tenant_api

app : FastAPI = FastAPI()
local_router = APIRouter(prefix="/local")
app.include_router(api, prefix="/api")
app.include_router(tenant_api, prefix="/api")
app.include_router(
    router=local_router,
    prefix="/v1",
)
app.mount(
    "/assets",
    StaticFiles(directory="public"),
    name="assets",
)


@local_router.get("/status")
def local_status(region: str = Query()):
    return {"region": region}

@app.get("/main")
def main():
    return "Hello World"
