from fastapi import APIRouter
from core.schemas import OrderIn

router = APIRouter(prefix="/api/v1")

@router.post("/orders")
def create_order(data: OrderIn):
    return data
