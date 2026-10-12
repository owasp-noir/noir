from typing import Annotated, Optional

from aws_lambda_powertools.event_handler import APIGatewayRestResolver
from aws_lambda_powertools.event_handler.openapi.params import Body, Header, Query

app = APIGatewayRestResolver(enable_validation=True)


@app.get("/validated/<todo_id>")
def get_todo(
    todo_id: str,
    limit: Annotated[int, Query()] = 1,
    x_tok: Annotated[str, Header(alias="X-Tok")] = "",
    x_request_id: Annotated[Optional[str], Header()] = None,
    completed: Optional[bool] = None,
):
    return {"id": todo_id}


@app.post("/validated")
def create(item: Annotated[dict, Body()]):
    return item
