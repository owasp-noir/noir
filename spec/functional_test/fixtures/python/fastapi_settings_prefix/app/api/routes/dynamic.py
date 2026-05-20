from fastapi import APIRouter

DYNAMIC_PREFIX = "/dynamic"

router = APIRouter(prefix=f"{DYNAMIC_PREFIX}/v1")


@router.get("/probe")
def read_probe():
    return {"ok": True}
