import http
from typing import FrozenSet, Optional,Union
from typing_extensions import Annotated
from fastapi.responses import JSONResponse
from fastapi import FastAPI, Path, Query, status, Body, Header, Cookie, Depends, Request, Response, APIRouter

api : APIRouter = APIRouter()
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

def registered_handler():
    return {"ok": True}

api.add_api_route(
    BASE_ROUTE + "/registered",
    registered_handler,
    methods=("POST",),
)
