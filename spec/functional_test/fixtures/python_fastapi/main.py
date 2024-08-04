import http
from typing import FrozenSet, Optional

from fastapi import FastAPI, Path, Query
from api import api

app : FastAPI = FastAPI()
app.include_router(api, prefix="/api")

@app.get("/main")
def main():
    return "Hello World"
