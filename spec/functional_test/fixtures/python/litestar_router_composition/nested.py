from litestar import Litestar, Router, Controller, get, post


@get("/{order_id:int}")
def get_order(order_id: int) -> dict:
    return {}


class ItemController(Controller):
    path = "/items"

    @get()
    async def list_items(self) -> list:
        return []


order_router = Router(path="/orders", route_handlers=[get_order])
item_router = Router(path="/catalog", route_handlers=[ItemController])
base_router = Router(path="/v01-base", route_handlers=[order_router, item_router])

app = Litestar(route_handlers=[base_router])
