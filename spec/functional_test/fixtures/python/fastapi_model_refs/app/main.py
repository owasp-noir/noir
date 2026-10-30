from typing import Annotated

from fastapi import FastAPI, File, Form, UploadFile
from pydantic import BaseModel

from app import base
from app.base import Loop, Owned as OwnedBase, Paged
from app.routes import router

app = FastAPI()
app.include_router(router)


class ItemBase(BaseModel):
    title: str


class ItemCreate(ItemBase):
    pass


class Note(OwnedBase):
    body: str


class Tagged(base.Owned):
    tag: str


class Listing(Paged[int]):
    query: str


class Login(BaseModel):
    username: str


class LoginWithOtp(Login):
    otp: str


@app.post("/items")
def create_item(item: ItemCreate):
    return item


@app.post("/notes")
def create_note(note: Note):
    return note


@app.post("/tags")
def create_tag(tagged: Tagged):
    return tagged


@app.post("/listings")
def list_items(listing: Listing):
    return listing


@app.post("/loops")
def create_loop(loop: Loop):
    return loop


@app.post("/login")
def login(data: Annotated[LoginWithOtp, Form()]):
    return data


@app.post("/upload")
def upload(file: UploadFile = File(...), caption: str = Form("")):
    return caption
