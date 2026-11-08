from pydantic import BaseModel


class ItemIn(BaseModel):
    name: str
    price: int
