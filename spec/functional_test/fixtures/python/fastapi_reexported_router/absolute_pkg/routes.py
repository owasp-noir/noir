from fastapi import APIRouter

router = APIRouter(prefix="/absolute")


@router.get("/whoami")
def whoami():
    pass
