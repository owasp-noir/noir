from fastapi import APIRouter

from app.schemas import ItemIn

router = APIRouter()


@router.post("/items")
def create_item(item: ItemIn):
    return item
