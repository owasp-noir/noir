from fastapi import FastAPI

from alias_pkg import users_router
from absolute_pkg import users_router as absolute_router
from api.routes import api_router
from direct_pkg.routes import router as direct_router
from relative_pkg import router as relative_router
from two_hop_pkg import router as two_hop_router

app = FastAPI()
app.include_router(relative_router, prefix="/api")
app.include_router(users_router, prefix="/api")
app.include_router(absolute_router, prefix="/api")
app.include_router(two_hop_router, prefix="/api")
app.include_router(direct_router, prefix="/api")
app.include_router(api_router)
