from fastapi import Depends, HTTPException, status

credentials_exception = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Could not validate credentials",
)


async def get_auth_token(token: str = "") -> str:
    return token


async def try_get_current_user(token: str = Depends(get_auth_token)) -> dict | None:
    try:
        return await get_current_user(token)
    except Exception:
        return None


async def get_current_user(token: str = Depends(get_auth_token)) -> dict:
    if not token:
        raise credentials_exception
    return {"token": token}


async def load_group(group_slug: str = "") -> dict:
    if not group_slug:
        raise HTTPException(404, "group not found")
    return {"slug": group_slug}
