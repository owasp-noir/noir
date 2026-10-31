from fastapi import APIRouter

router = APIRouter(prefix="/session")


@router.post("/start")
async def start():
    return {}
