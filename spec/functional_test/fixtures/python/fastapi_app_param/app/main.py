from fastapi import FastAPI

from app.users import (
    router as users_router,
)
from app.views import init_views

app = FastAPI()
app.include_router(users_router, prefix="/api")
init_views(app)
