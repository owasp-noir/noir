from uuid import UUID

from fastapi import APIRouter, Depends, Response


def mark(response: Response):
    response.headers["X-Catalog"] = "books"


def mark_write(response: Response):
    response.headers["X-Operation"] = "write"


books = APIRouter(dependencies=[Depends(mark)])


@books.get("/books")
@books.post("/books", dependencies=[Depends(mark_write)])
def collection():
    return []


@books.get("/books/{id}")
def book(id: str):
    return id


@books.get("/edition")
@books.get("/edition/{year:int}")
def edition(year: int = 2025):
    return year


@books.get("/price/{amount:float}")
def price(amount: float):
    return amount


@books.get("/authors/{author:uuid}")
def author(author: UUID):
    return author


@books.get("/files/{name:path}")
@books.get("/titles/{name:str}")
def file_name(name: str):
    return name
