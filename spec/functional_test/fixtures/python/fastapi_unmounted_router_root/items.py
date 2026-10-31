from fastapi import APIRouter

router = APIRouter(prefix="/items")


@router.get("/{item_id}")
async def get_item(item_id: int):
    return {"id": item_id}
