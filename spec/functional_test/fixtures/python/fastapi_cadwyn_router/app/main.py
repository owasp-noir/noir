from fastapi import FastAPI

from app.parent import authenticated_router
from app.routes import plain, router

app = FastAPI()
app.include_router(router, prefix="/dag-runs")
app.include_router(plain, prefix="/dags")
app.include_router(authenticated_router, prefix="/execution")
