from fastapi import APIRouter

router = APIRouter()


@router.get("/probe")
def read_factory_probe():
    return {"ok": True}
