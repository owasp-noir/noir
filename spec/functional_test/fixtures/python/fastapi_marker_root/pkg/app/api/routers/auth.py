from fastapi import APIRouter
auth_router = APIRouter(prefix="/v1/auth")

@auth_router.get("/me")
async def me():
    return {}
