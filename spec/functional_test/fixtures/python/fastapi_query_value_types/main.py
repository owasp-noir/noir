from datetime import date, datetime
from decimal import Decimal
from enum import Enum, IntEnum, StrEnum
from typing import Literal, Optional
from uuid import UUID

from fastapi import BackgroundTasks, FastAPI, Response
from pydantic import BaseModel, PositiveInt, conint

app = FastAPI()


class SortOrder(StrEnum):
    asc = "asc"
    desc = "desc"


class Kind(Enum):
    a = "a"


class Level(IntEnum):
    low = 1


class Color(str, Enum):
    red = "red"


class Item(BaseModel):
    name: str


# Every annotation that is no model is a query value.
@app.get("/orders")
def list_orders(
    customer_id: UUID,
    start: date | None = None,
    end: Optional[datetime] = None,
    min_total: Decimal = Decimal("0"),
    status: Literal["open", "closed"] = "open",
    order: SortOrder = SortOrder.asc,
    kind: Kind = Kind.a,
    level: Level = Level.low,
    color: Color = Color.red,
    limit: conint(gt=0) = 10,
    page: PositiveInt = 1,
    q: str = "",
):
    return []


# Injected classes are not request parameters; a model is still the body.
@app.post("/items")
def create_item(item: Item, response: Response, tasks: BackgroundTasks):
    return {}
