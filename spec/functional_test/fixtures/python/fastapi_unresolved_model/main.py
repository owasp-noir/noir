from datetime import date
from enum import Enum
from uuid import UUID

from fastapi import BackgroundTasks, FastAPI, Request
from shared_models.schemas import (
    AckRequest,
)


class Color(str, Enum):
    red = "red"


app = FastAPI()


# `AckRequest` lives in a package outside the scan: still the body.
@app.post("/acks/{item_id}")
def ack(item_id: str, payload: AckRequest, tasks: BackgroundTasks, request: Request):
    return {}


# Stdlib and local Enum types are query values, never a body.
@app.get("/days/{day_id}")
def day(day_id: UUID, on: date, color: Color):
    return {}
