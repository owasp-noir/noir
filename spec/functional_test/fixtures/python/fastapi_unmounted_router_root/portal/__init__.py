from fastapi import APIRouter

from .account.views import router as account_router
from .orders import router as orders_router

router = APIRouter(prefix="/portal")

router.include_router(orders_router)
router.include_router(account_router)
