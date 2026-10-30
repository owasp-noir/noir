from typing import Generic, TypeVar

import pydantic

T = TypeVar("T")


class Owned(pydantic.BaseModel):
    owner_id: int


class Paged(pydantic.BaseModel, Generic[T]):
    page: int = 1


class Loop(Pool):
    loop_note: str


class Pool(Loop):
    pool_size: int
