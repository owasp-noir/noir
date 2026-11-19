from fastapi import APIRouter, FastAPI

app = FastAPI()
api_router = APIRouter(prefix="/api")

from srv import routes, items

app.include_router(api_router)
