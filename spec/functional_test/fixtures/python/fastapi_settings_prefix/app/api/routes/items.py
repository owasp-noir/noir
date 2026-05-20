# Regression for fastapi-template's `APIRouter(prefix="/items")`
# pattern: the router-level prefix must be preserved when the
# parent layers its own prefix on top (via include_router).
# Routes inside should surface at `/api/v1/items/...`, not
# `/api/v1/...`.
from fastapi import APIRouter

ITEMS_PREFIX = "/items"

router = APIRouter(
    prefix=ITEMS_PREFIX,
    tags=["items"],
)


@router.get("/")
def read_items():
    return []


@router.get("/{id}")
def read_item(id: int):
    return {"id": id}
