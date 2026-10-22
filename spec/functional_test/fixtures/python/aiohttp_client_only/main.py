from fastapi import FastAPI

from routers import auths

app = FastAPI()
app.include_router(auths.router, prefix="/api/v1/auths")
