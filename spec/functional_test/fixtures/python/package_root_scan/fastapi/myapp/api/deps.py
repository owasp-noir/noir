from typing import Annotated
from fastapi import Depends, HTTPException


def get_current_user(token: str):
    if not token:
        raise HTTPException(status_code=401)
    return {}


def require_admin(user: dict = Depends(get_current_user)):
    if not user.get("is_admin"):
        raise HTTPException(status_code=403)
    return user


AdminUser = Annotated[dict, Depends(require_admin)]
