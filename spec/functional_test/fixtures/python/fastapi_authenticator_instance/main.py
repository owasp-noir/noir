from fastapi import FastAPI

from flag_endpoints import router as flags_router
from items.endpoints import router as items_router

app = FastAPI()
app.include_router(items_router)
app.include_router(flags_router)
