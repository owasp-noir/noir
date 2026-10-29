from typing import Annotated
from fastapi import FastAPI, Depends, Query
from app.service import CommonParameters, MultiLine
from app import star

app = FastAPI()
app.include_router(star.router)


def local_dep(token: str = Query(...)):
    return token


LocalDep = Annotated[str, Depends(local_dep)]
Limit = Annotated[int, Query(alias="maxItems")]


@app.get("/aliased")
def aliased(common: CommonParameters):
    return common


@app.get("/multiline")
def multiline(common: MultiLine):
    return common


@app.get("/local")
def local(tok: LocalDep, limit: Limit = 10):
    return tok
