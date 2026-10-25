from fastapi import APIRouter, Depends, Header, Path

router = APIRouter(prefix="/groups/{group_slug}")


def get_locale(accept_language: str | None = Header(None)) -> str:
    return accept_language or "en-US"


def load_group(group_slug: str = Path(...)) -> dict:
    return {"slug": group_slug}


class BaseView:
    locale: str = Depends(get_locale)


def controller(r):
    return lambda cls: cls


@controller(router)
class GroupView(BaseView):
    group: dict = Depends(load_group)

    @router.get("/items/{item_id}")
    def get_item(self, item_id: str, page: int = 1):
        return {}
