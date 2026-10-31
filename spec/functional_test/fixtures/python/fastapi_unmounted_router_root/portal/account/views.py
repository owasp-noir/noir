from fastapi import APIRouter

from ..session import router as session_router

router = APIRouter(prefix="/account")
router.include_router(session_router)


@router.get("/me")
async def me():
    return {}
