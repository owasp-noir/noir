from fastapi import FastAPI

from myapp import api
from myapp.modules import auth, billing

app = FastAPI()
# `auth` is a package whose __init__.py re-exports `router`.
app.include_router(auth.router, prefix="/auth")
app.include_router(billing.router, prefix="/billing")
app.include_router(api.v1.users.router, prefix="/api/v1")
