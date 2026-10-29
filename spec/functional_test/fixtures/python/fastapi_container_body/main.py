from typing import Annotated, Any, List, Optional

from fastapi import FastAPI, Query

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
