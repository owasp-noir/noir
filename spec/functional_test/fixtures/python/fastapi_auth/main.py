from fastapi import FastAPI, Depends, HTTPException, Security
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


class Item(BaseModel):
    owner_id: int


async def get_current_active_superuser(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_superuser:
        raise HTTPException(status_code=403, detail="Not enough privileges")
    return current_user


@app.delete("/users/{user_id}", dependencies=[Depends(get_current_active_superuser)])
async def delete_user(user_id: int):
    return {"deleted": user_id}


@app.put("/items/{item_id}")
async def update_item(item_id: int, current_user: User = Depends(get_current_user)):
    item = Item(owner_id=1)
    if item.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not enough permissions")
    return {"item": item_id}


@app.patch("/notes/{note_id}")
async def update_note(note_id: int, current_user: User = Depends(get_current_user)):
    return {"note": note_id}


ENABLE_SIGNUP = False


async def get_optional_user(token: str | None = Depends(oauth2_scheme)) -> User | None:
    return None


@app.post("/signup")
async def signup():
    if not ENABLE_SIGNUP:
        raise HTTPException(status_code=403, detail="Signup disabled")
    return {}


@app.get("/config")
async def config(user: User | None = Depends(get_optional_user)):
    if user is not None and user.is_admin:
        return {"admin": True}
    return {}


@app.delete("/drafts/{draft_id}")
async def delete_draft(draft_id: int, user: User | None = Depends(get_optional_user)):
    if user is None:
        raise HTTPException(status_code=401, detail="Login required")
    return {}


@app.post("/posts/{post_id}/pin")
async def pin_post(post_id: int, user: User | None = Depends(get_optional_user)):
    if user and not user.is_admin:
        raise HTTPException(status_code=403)
    return {}
