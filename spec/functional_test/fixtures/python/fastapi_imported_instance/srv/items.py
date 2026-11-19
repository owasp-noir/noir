from .application import api_router


@api_router.get("/items/{item_id}")
def get_item(item_id: int, q: str = ""):
    return {}
