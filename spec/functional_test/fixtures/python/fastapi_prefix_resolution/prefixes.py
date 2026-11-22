from fastapi import APIRouter

API_PREFIX = "/constant"

actual_router = APIRouter()
exported = actual_router


@actual_router.get("/entry")
def entry():
    return {}
