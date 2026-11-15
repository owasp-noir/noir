from fastapi import FastAPI
from a.api.routers import auth

app = FastAPI()
app.include_router(auth.auth_router, prefix="/api")
