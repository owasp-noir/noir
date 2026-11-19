from fastapi import APIRouter

router = APIRouter()


@router.get("/users")
def users():
    return []
