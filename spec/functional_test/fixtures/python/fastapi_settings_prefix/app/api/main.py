from fastapi import APIRouter

from app.api.routes import login, items, dynamic

api_router = APIRouter()
api_router.include_router(login.router)
api_router.include_router(
    router=items.router,
    tags=["items"],
)
api_router.include_router(dynamic.router)
