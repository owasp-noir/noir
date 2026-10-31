from fastapi import APIRouter

from items import router as items_router

# Never mounted and never handed to a helper: its own routes keep its prefix,
# but it does not lend that prefix to the routers it includes.
dead_router = APIRouter(prefix="/legacy")
dead_router.include_router(items_router)


@dead_router.get("/ping")
async def ping():
    return "pong"
