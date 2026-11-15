from fastapi import APIRouter

router = APIRouter(prefix="/users")


@router.get("/whoami")
def whoami():
    pass
