from fastapi import Request
from fastapi.responses import JSONResponse


def login_enabled() -> bool:
    return True


def signed_in_user(request: Request):
    return request.cookies.get("demo_session")


def sign_in_required() -> JSONResponse:
    return JSONResponse(
        {"detail": "sign in first"},
        status_code=401,
    )
