from fastapi import APIRouter

router = APIRouter()


@router.post("/login/access-token")
def login_access_token():
    return {"token": "ok"}


@router.post("/login/test-token")
def login_test_token():
    return {"ok": True}
