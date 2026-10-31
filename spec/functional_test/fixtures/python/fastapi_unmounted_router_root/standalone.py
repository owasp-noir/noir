from fastapi import APIRouter

# Included nowhere: served (if at all) under its own prefix, as before.
router = APIRouter(prefix="/standalone")


@router.get("/ping")
async def ping():
    return "pong"
