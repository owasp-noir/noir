from fastapi import FastAPI
from app.schemas.orders import OrderIn
from shared.schemas.refunds import RefundIn
# `common` is in both `shared/` and `libs/`: which one runs is unknowable.
from common.notes import NoteIn

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
