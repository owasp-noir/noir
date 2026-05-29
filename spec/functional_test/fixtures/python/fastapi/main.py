import http
import fastapi
from typing import FrozenSet, Optional

from fastapi import APIRouter, FastAPI, Path, Query
from fastapi.staticfiles import StaticFiles
from api import api
from api import tenant_api

app : fastapi.FastAPI = fastapi.FastAPI()
local_router : fastapi.APIRouter = fastapi.APIRouter(prefix="/local")
app.include_router(api, prefix="/api")
app.include_router(tenant_api, prefix="/api")
app.include_router(
    router=local_router,
    prefix="/v1",
)
# app.include_router(api, prefix="/commented")
# app.add_api_route("/commented", main, methods=["GET"])
# app.mount("/commented-static", StaticFiles(directory="public"), name="commented")
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
