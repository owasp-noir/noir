from typing import Annotated, Any, Dict, List, Optional

from fastapi import Depends, FastAPI, Query

app = FastAPI()


@app.post("/items")
def create_item(payload: dict[str, Any], tags: list[str]):
    return {"name": payload.get("name"), "tags": tags}


@app.get("/search")
def search(
    q: Optional[str] = None,
    labels: Annotated[list[str], Query()] = [],
    ids: List[int] = Query([]),
):
    return {"q": q, "labels": labels, "ids": ids}


@app.post("/bulk")
def bulk(names: Optional[List[str]] = None):
    return names


def parse_ids(raw: str = Query("")):
    return [int(x) for x in raw.split(",")]


@app.get("/picked")
def picked(ids: Annotated[list[int], Depends(parse_ids)]):
    return ids


def get_session():
    return None


# A lone dict body is the request body itself: its keys are the fields.
@app.post("/orders")
def create_order(payload: dict[str, Any], session=Depends(get_session)):
    return {"label": payload["label"], "lines": payload.get("lines", [])}


@app.post("/orders/{order_id}/notes")
def add_note(order_id: int, payload: Optional[Dict[str, Any]] = None):
    return {"note": payload.get("note")}


# No key read: the body stays one opaque field.
@app.post("/orders/raw")
def raw_order(payload: dict[str, Any]):
    return payload
