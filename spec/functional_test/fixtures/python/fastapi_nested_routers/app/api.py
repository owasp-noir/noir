from fastapi import APIRouter, Query

# users_router is an aliased import (count == 0); items is a
# module-alias re-export resolving to app/items/api.py.
from app.users import router as users_router
from app.items import api as items

router = APIRouter()
secure_router = APIRouter(prefix="/secure")
admin_router = APIRouter()

# Child via alias import.
router.include_router(users_router, prefix="/users")
# Child via module-alias re-export (app/items/api.py defines `router`).
router.include_router(items.router)
# Local nested router chaining: secure_router lives in THIS file and
# carries its own constructor prefix, and itself includes another local
# router. Both levels must inherit the /api root prefix.
router.include_router(secure_router)
secure_router.include_router(admin_router, prefix="/admin")


@router.get("/ping")
def ping(q: str = Query()):
    return {"q": q}


@admin_router.get("/dashboard")
def dashboard():
    return {"ok": True}
