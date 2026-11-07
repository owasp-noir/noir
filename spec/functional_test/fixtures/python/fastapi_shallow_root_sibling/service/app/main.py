from fastapi import FastAPI

from app.routes import router
from shared import auth
from shared import db

app = FastAPI()
app.include_router(router, prefix="/api")
