from fastapi import APIRouter

router = APIRouter(prefix="/orders")


@router.get("/")
async def list_orders():
    return []
