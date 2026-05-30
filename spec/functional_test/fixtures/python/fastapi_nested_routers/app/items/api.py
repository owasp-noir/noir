from fastapi import APIRouter

from app.items.handlers import router as handlers_router

router = APIRouter(prefix="/items")

# Re-export: this package-level `router` aggregates the handlers router.
router.include_router(handlers_router)
