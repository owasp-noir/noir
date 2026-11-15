import os

from fastapi import APIRouter

BASE = os.getenv("EXTERNAL_API_BASE", "")
external_router = APIRouter(prefix=BASE + "/external")
outer_router = APIRouter(prefix=BASE + "/outer")
outer_router.include_router(external_router, prefix=BASE + "/nested")


@external_router.get("/item")
def external_item():
    return {}
