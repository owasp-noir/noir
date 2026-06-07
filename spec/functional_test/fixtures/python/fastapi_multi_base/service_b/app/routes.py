from fastapi import APIRouter

router = APIRouter()


@router.get("/service-b")
def service_b():
    return {"service": "b"}
