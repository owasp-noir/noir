from fastapi import FastAPI

from app.routes import router
from shared import auth

app = FastAPI()
app.include_router(router, prefix="/api")
