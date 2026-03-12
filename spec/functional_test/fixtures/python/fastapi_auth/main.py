from fastapi import FastAPI, Depends, Security
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel

app = FastAPI()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")


class User(BaseModel):
    username: str


async def get_current_user(token: str = Depends(oauth2_scheme)) -> User:
    # Mock: decode token and return user
    return User(username="testuser")


@app.get("/public")
async def public_page():
    return {"message": "public"}


@app.get("/profile")
async def profile(current_user: User = Depends(get_current_user)):
    return {"user": current_user}


@app.get("/admin")
async def admin(token: str = Security(oauth2_scheme)):
    return {"admin": True}


@app.get("/open")
async def open_page():
    return {"message": "open"}
