from fastapi import Header, HTTPException


def verify_api_key(x_api_key: str = Header(...)):
    if x_api_key != "secret":
        raise HTTPException(status_code=403)


def require_staff(authorization: str = Header(None)):
    if authorization is None:
        raise HTTPException(status_code=401)
