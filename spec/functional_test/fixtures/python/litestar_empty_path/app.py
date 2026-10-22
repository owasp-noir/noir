from litestar import Controller, get, post, Litestar
from pydantic import BaseModel


class ItemCreate(BaseModel):
    name: str


# Bare @get()/@post() default to path="" → "/".
@get()
async def index() -> dict:
    return {}


@post(sync_to_thread=False)
async def create_root() -> dict:
    return {}


class ItemController(Controller):
    path = "/items"

    # Empty method path joins with controller prefix → "/items".
    @get()
    async def list_items(self) -> list:
        return []

    @post()
    async def create_item(self, data: ItemCreate) -> dict:
        return {}


app = Litestar(route_handlers=[index, create_root, ItemController])
