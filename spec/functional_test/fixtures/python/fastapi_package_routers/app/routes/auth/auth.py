from fastapi import APIRouter

from app.routes._base.routers import UserAPIRouter

public_router = APIRouter()
user_router = UserAPIRouter(
    prefix="",
)


@public_router.post("/token")
def get_token():
    return {}


@user_router.post("/refresh")
def refresh():
    return {}
