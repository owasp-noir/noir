from fastapi import APIRouter

router = APIRouter(prefix="/two-hop")


@router.get("/whoami")
def whoami():
    pass
