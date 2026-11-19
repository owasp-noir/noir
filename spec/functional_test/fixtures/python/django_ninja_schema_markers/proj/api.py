from typing import List, Optional

from ninja import Form, NinjaAPI, Path, Query, Schema
from pydantic import Field

api = NinjaAPI()


class Filters(Schema):
    limit: int = 100
    offset: int = None
    query: str = None
    category__in: List[str] = Field(None, alias="categories")


class PathDate(Schema):
    year: int
    month: int
    day: int


class Item(Schema):
    name: str
    description: Optional[str] = None
    price: float


# docs: Query parameters > Using Schema
@api.get("/filter")
def events(request, filters: Query[Filters]):
    return {"filters": filters.dict()}


# pre-1.0 spelling of the same thing
@api.get("/filter-legacy")
def events_legacy(request, filters: Filters = Query(...)):
    return {"filters": filters.dict()}


# docs: Path parameters > Using Schema
@api.get("/events/{year}/{month}/{day}")
def events_by_date(request, date: Path[PathDate]):
    return {}


# docs: Form data > Using a Schema
@api.post("/items")
def create_item(request, item: Form[Item]):
    return item


# control: a body schema IS expanded today
@api.post("/items-json")
def create_item_json(request, item: Item):
    return item
