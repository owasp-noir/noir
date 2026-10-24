from fastapi import Depends

from app.deps import get_current_user, load_group


class BaseController:
    session: str = Depends(lambda: "session")


class BasePublicController(BaseController):
    group: dict = Depends(load_group)


class BaseUserController(BaseController):
    user: dict = Depends(get_current_user)


class BaseCrudController(BaseUserController):
    pass
