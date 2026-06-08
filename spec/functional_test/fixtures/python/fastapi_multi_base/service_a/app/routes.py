from fastapi import APIRouter

router = APIRouter()


@router.get("/service-a")
def service_a():
    return {"service": "a"}
