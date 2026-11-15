from fastapi import APIRouter

from api.v1 import users_router

router = APIRouter()
router.include_router(users_router, prefix="/v1")
