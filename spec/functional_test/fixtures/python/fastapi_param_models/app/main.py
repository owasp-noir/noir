from typing import Annotated

from fastapi import Depends, FastAPI, Query

from app.schema import FeedQuery, LoginForm, Registration
from app.views import router

app = FastAPI()
app.include_router(router)


@app.post("/register")
def register(data: Registration):
    return {}


@app.post("/token")
def token(form: LoginForm = Depends()):
    return {}


@app.get("/feed")
def feed(q: Annotated[FeedQuery, Query()]):
    return {}
