from typing import Annotated

from fastapi import Body, FastAPI
from app.schemas.orders import OrderIn
from shared.schemas.refunds import RefundIn
# `common` is in both `shared/` and `libs/`: which one runs is unknowable.
from common.notes import NoteIn
from external_notes import ExternalNote

app = FastAPI()

@app.post("/orders")
def create_order(data: OrderIn):
    return data

@app.post("/refunds")
def create_refund(data: RefundIn):
    return data

@app.post("/notes")
def create_note(data: NoteIn):
    return data

@app.post("/notes/embedded")
def create_embedded_note(data: Annotated[NoteIn, Body(embed=True)]):
    return data

@app.post("/notes/pair")
def create_note_pair(first: OrderIn, second: NoteIn = Body()):
    return first, second

@app.post("/notes/external")
def create_external_note(data: ExternalNote = Body(), preview: bool = False):
    return data
