from fastapi import APIRouter, Depends

from app.base import BaseCrudController, BasePublicController, UserAPIRouter
from app.deps import try_get_current_user

router = APIRouter(prefix="/items")
user_router = UserAPIRouter(prefix="/me")


def controller(r):
    return lambda cls: cls


@router.get("/name")
async def check_name(name: str, user=Depends(try_get_current_user)):
    return {"name": name}


@user_router.get("")
async def me():
    return {}


@controller(router)
class ItemController(BaseCrudController):
    @router.delete("/{item_id}")
    async def delete_one(self, item_id: str):
        return {}


@controller(router)
class PublicItemController(BasePublicController):
    @router.get("/public/{item_id}")
    async def get_public(self, item_id: str):
        return {}
