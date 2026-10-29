from typing import Annotated
from fastapi import Depends, Query


def common_parameters(
    page: int = Query(1, gt=0),
    items_per_page: int = Query(5, alias="itemsPerPage"),
    query_str: str = Query(None, alias="q"),
):
    return {"page": page, "items_per_page": items_per_page, "query_str": query_str}


CommonParameters = Annotated[dict, Depends(common_parameters)]

MultiLine = Annotated[
    dict,
    Depends(common_parameters),
]
