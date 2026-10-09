from fastapi import APIRouter, FastAPI

app = FastAPI()
router = APIRouter()
outer = APIRouter(prefix="/outer")


@router.get("/ping")
def ping():
    return {}


# One router included under two prefixes is served at both.
app.include_router(router, prefix="/v1")
app.include_router(router, prefix="/v2")

# ...and reached again through a second parent.
outer.include_router(router)
app.include_router(outer)
