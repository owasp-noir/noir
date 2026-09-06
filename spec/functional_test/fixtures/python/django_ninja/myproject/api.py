from ninja import NinjaAPI, Schema, Form, File, Header, Cookie, Query, Field
from ninja.files import UploadedFile

from events.api import router as events_router
from myproject.schemas import BlogIn
from blog import api as blog_api

api = NinjaAPI()


class ItemIn(Schema):
    name: str
    price: float
    quantity: int = 1


class AliasedIn(Schema):
    user_name: str = Field(..., alias="userName")
    age: int


# django-ninja names a parameter `alias or <identifier>`, so an alias
# replaces the identifier outright — `renamed` is never populated from a
# `renamed` header. There is no underscore rule here (Django's HttpHeaders
# resolves `x_api_key` and `x-api-key` to the same header), which is why
# `/api/whoami` above still expects `x_api_key`.
@api.get("/aliased")
def aliased(request, renamed: str = Header(None, alias="X-Custom"), q_n: str = Query(None, alias="q-n")):
    return {}


@api.post("/aliased_body")
def aliased_body(request, payload: AliasedIn):
    return payload


@api.get("/add")
def add(request, a: int, b: int):
    return {"result": a + b}


@api.post("/items")
def create_item(request, item: ItemIn):
    return item


@api.get("/items/{int:item_id}")
def get_item(request, item_id: int, q: str = None):
    return {"item_id": item_id, "q": q}


@api.put("/items/{item_id}")
def update_item(request, item_id: int, item: ItemIn):
    return item


@api.get("/search")
def search(request, q: str, limit: int = 10):
    return []


@api.post("/upload")
def upload(request, note: str = Form(...), attachment: UploadedFile = File(...)):
    return {"name": attachment.name, "note": note}


@api.get("/whoami")
def whoami(request, x_api_key: str = Header(...), session: str = Cookie(None)):
    return {}


@api.post(
    "/blogs",
    response={201: dict},
)
def create_blog(request, blog: BlogIn):
    return blog


@api.api_operation(["POST", "PATCH"], "/mixed")
def mixed(request):
    return {}


api.add_router("/events/", events_router)
api.add_router("/news/", "news.api.router")
api.add_router("/blog/", blog_api.router)
