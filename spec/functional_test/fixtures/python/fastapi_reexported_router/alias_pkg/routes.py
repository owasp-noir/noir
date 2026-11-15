from fastapi import APIRouter

router = APIRouter(prefix="/alias")


@router.get("/whoami")
def whoami():
    pass
