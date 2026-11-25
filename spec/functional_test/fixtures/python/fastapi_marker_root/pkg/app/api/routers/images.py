from fastapi import APIRouter
images_router = APIRouter(prefix="/v1/images")

@images_router.get("/list")
async def lst():
    return {}
