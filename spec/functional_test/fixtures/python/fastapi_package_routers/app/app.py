from fastapi import FastAPI

from app.routes import router
from app.routes.media import media_router

app = FastAPI(
    title="x",
)


def api_routers():
    app.include_router(router)
    app.include_router(media_router)


api_routers()
