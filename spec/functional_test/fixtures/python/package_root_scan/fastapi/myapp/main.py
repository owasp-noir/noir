from fastapi import FastAPI
from myapp.api.routers import users

app = FastAPI()
app.include_router(users.router, prefix="/api")
