from fastapi import APIRouter, Depends, FastAPI

from app import views
from app.deps import require_staff, verify_api_key

staff_router = APIRouter(prefix="/staff", dependencies=[Depends(require_staff)])
staff_router.include_router(views.reports_router)
staff_router.include_router(views.shared_router)

public_router = APIRouter()
public_router.include_router(views.status_router)
public_router.include_router(views.shared_router)

app = FastAPI()
app.include_router(staff_router)
app.include_router(public_router)


def create_internal_app():
    internal = FastAPI(dependencies=[Depends(verify_api_key)])
    internal.include_router(views.jobs_router)
    return internal


app.mount("/internal", create_internal_app())
