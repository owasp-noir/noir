from fastapi import APIRouter

inner_router = APIRouter()


@inner_router.get("/client/{client_secret}")
async def client_get(client_secret: str):
    return {}


router = APIRouter(prefix="/checkouts")
router.include_router(inner_router, prefix="/custom")
router.include_router(inner_router)
