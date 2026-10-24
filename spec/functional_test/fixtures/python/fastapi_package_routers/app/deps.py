from fastapi import HTTPException


async def get_current_user(token: str = ""):
    if not token:
        raise HTTPException(status_code=401)
    return token
