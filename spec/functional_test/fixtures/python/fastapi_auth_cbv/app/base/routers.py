from fastapi import APIRouter, Depends

from app.deps import get_current_user


class UserAPIRouter(APIRouter):
    def __init__(self, prefix: str = "", **kwargs):
        super().__init__(prefix=prefix, dependencies=[Depends(get_current_user)], **kwargs)
