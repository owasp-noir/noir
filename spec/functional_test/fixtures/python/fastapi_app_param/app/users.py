from fastapi import APIRouter

router = APIRouter(prefix="/users")


@router.get("/me")
def me():
    return {}
