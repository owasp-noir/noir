from fastapi import APIRouter, FastAPI

items_router = APIRouter(prefix="/items")


@items_router.get("/{item_id}")
def get_item(item_id: int):
    return {}


public_router = APIRouter(prefix="/api/v2")
public_router.include_router(items_router)


def init_views(app: FastAPI) -> None:
    app.include_router(public_router)

    @app.get("/health")
    def health():
        return {}
