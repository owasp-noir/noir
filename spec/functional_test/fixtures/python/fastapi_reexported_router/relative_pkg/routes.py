from fastapi import APIRouter

router = APIRouter(prefix="/relative")


@router.get("/whoami")
def whoami():
    pass
