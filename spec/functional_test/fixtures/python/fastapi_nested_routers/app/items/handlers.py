from fastapi import APIRouter

router = APIRouter()


@router.get("/{item_id}")
def get_item(item_id: int):
    return {"item_id": item_id}
