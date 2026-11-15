from fastapi import APIRouter

auth_router = APIRouter(prefix="/v1/shallow")


@auth_router.get("/me")
async def me():
    return {}
