from fastapi import APIRouter

router = APIRouter(prefix="/direct")


@router.get("/whoami")
def whoami():
    pass
