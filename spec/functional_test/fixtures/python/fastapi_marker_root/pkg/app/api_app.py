from fastapi import FastAPI
from pkg.app.api.routers import (
    auth,
    images,
)

app = FastAPI()
app.include_router(auth.auth_router, prefix="/api")
app.include_router(images.images_router, prefix="/api")
