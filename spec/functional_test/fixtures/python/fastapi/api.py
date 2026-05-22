import http
import external_handlers
from typing import FrozenSet, Optional,Union
from fastapi_utils.cbv import cbv
from typing_extensions import Annotated
from fastapi.responses import JSONResponse
from fastapi import FastAPI, Path, Query, status, Body, Header, Cookie, Depends, Security, Request, Response, APIRouter, WebSocket

api : APIRouter = APIRouter()
tenant_api = APIRouter(prefix="/tenants/{tenant_id}")
BASE_ROUTE = "/constant"
KEYWORD_ROUTE = "/keyword"

@api.get("/query/param-required/int")
def get_query_param_required_type(query: int = Query()):
    return f"foo bar {query}"

@api.put("/items/{item_id}")
async def upsert_item(
    item_id: str,
    name: Annotated[Union[str, None], Body()] = None,
    size: Annotated[Union[int, None], Body()] = None,
):
    items = {"foo": {"name": "Fighters", "size": 6}, "bar": {"name": "Tenders", "size": 3}}
    if item_id in items:
        item = items[item_id]
        item["name"] = name
        item["size"] = size
        return item
    else:
        item = {"name": name, "size": size}
        items[item_id] = item
        return JSONResponse(status_code=status.HTTP_201_CREATED, content=item)

@api.get("/hidden_header")
async def hidden_header(
    hidden_header: Optional[str] = Header(default=None, include_in_schema=False)
):
    return {"hidden_header": hidden_header}


@api.get("/cookie_examples/")
def cookie_examples(
    data: Union[str, None] = Cookie(
        default=None,
        examples=["json_schema_cookie1", "json_schema_cookie2"],
        openapi_examples={
            "Cookie One": {
                "summary": "Cookie One Summary",
                "description": "Cookie One Description",
                "value": "cookie1",
            },
            "Cookie Two": {
                "value": "cookie2",
            },
        },
    ),
):
    return data

@api.post("/dummypath")
async def get_body(request: Request):
    jj = request.json()
    return await jj["dummy"]

@api.get(BASE_ROUTE + "/concat")
def constant_concat_route():
    return {"ok": True}

@api.get(path=f"{KEYWORD_ROUTE}/fstring")
def keyword_fstring_route(q: int = Query()):
    return {"q": q}

@api.get(path=f"{KEYWORD_ROUTE}/items/{{item_id}}")
def escaped_brace_fstring_route(item_id: int):
    return {"item_id": item_id}

def resolve_account_id() -> int:
    return 1

def resolve_api_key() -> str:
    return "secret"

@api.get("/dependency/items/{item_id}")
def dependency_route(
    item_id: int,
    account_id: int = Depends(resolve_account_id),
    api_key: str = Security(resolve_api_key),
    q: str = Query(),
):
    return {"item_id": item_id, "account_id": account_id, "api_key": api_key, "q": q}

@cbv(api)
class ItemViews:
    @api.get("/cbv/items/{item_id}")
    def get_item(self, item_id: int, include_meta: bool = Query(False)):
        return {"item_id": item_id, "include_meta": include_meta}

def registered_handler():
    return {"ok": True}


def registered_item_handler(
    item_id: int,
    q: int = Query(),
    payload: Annotated[Union[str, None], Body()] = None,
):
    return {"item_id": item_id, "q": q, "payload": payload}


def tenant_registered_handler(
    tenant_id: str,
    q: int = Query(),
):
    return {"tenant_id": tenant_id, "q": q}


@api.websocket("/ws/{room_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    room_id: str,
    token: str = Query(),
):
    await websocket.accept()
    await websocket.send_json({"room_id": room_id, "token": token})
    await websocket.close()


async def registered_websocket_handler(
    websocket: WebSocket,
    channel: str,
    client_id: str = Query(),
):
    await websocket.accept()
    await websocket.send_json({"channel": channel, "client_id": client_id})
    await websocket.close()

api.add_api_route(
    BASE_ROUTE + "/registered",
    registered_handler,
    methods=("POST",),
)

api.add_api_route(
    f"{BASE_ROUTE}/registered/{{item_id}}",
    endpoint=registered_item_handler,
    methods=["PUT"],
)

api.add_api_route(
    "/external/{item_id}",
    endpoint=external_handlers.external_item_handler,
    methods=["PATCH"],
)

tenant_api.add_api_route(
    "/registered",
    endpoint=tenant_registered_handler,
    methods=["GET"],
)

api.add_api_websocket_route(
    "/ws/registered/{channel}",
    endpoint=registered_websocket_handler,
)
