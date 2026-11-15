from fastapi import APIRouter

auth_router = APIRouter(prefix="/v1/three")


@auth_router.get("/me")
async def me():
    return {}
