from fastapi import APIRouter
from myapp.api.deps import AdminUser

router = APIRouter(prefix="/v1/auth")


@router.get("/users")
def list_users(user: AdminUser):
    return []
