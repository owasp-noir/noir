from fastapi import APIRouter

from checkout import router as checkout_router
from items import router as items_router
from portal import router as portal_router

router = APIRouter(prefix="/v1")

router.include_router(items_router)
router.include_router(portal_router)
router.include_router(checkout_router)
