from ninja import NinjaAPI, Schema, Form, File, Header, Cookie
from ninja.files import UploadedFile

from events.api import router as events_router
from myproject.schemas import BlogIn
from blog import api as blog_api

api = NinjaAPI()


class ItemIn(Schema):
    name: str
    price: float
    quantity: int = 1


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
