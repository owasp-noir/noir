from fastapi import APIRouter
from app.deps import *

router = APIRouter()


@router.get("/tenant")
def tenant_view(t: Tenant):
    return t
