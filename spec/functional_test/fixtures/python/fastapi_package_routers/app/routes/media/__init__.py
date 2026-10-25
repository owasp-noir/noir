from fastapi import APIRouter

media_router = APIRouter(prefix="/api/media")


@media_router.get("/validate.txt")
def validate():
    return 1
