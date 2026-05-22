from typing import Union

from fastapi import Body, Query
from typing_extensions import Annotated


def external_item_handler(
    item_id: int,
    q: str = Query(),
    payload: Annotated[Union[str, None], Body()] = None,
):
    return {"item_id": item_id, "q": q, "payload": payload}
