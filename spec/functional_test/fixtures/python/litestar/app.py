from litestar import Litestar, get, post, put, delete, route, Router
from litestar.connection import Request
from pydantic import BaseModel


class UserCreate(BaseModel):
    name: str
    email: str


class UserUpdate(BaseModel):
    name: str


@get("/")
async def index() -> dict:
    return {}


@get("/users")
async def list_users() -> list:
    return []


@get("/users/{user_id:int}")
async def get_user(user_id: int) -> dict:
    return {"id": user_id}


@post("/users")
async def create_user(data: UserCreate) -> dict:
    return {}


@put("/users/{user_id:int}")
async def update_user(user_id: int, data: UserUpdate) -> dict:
    return {}


@delete("/users/{user_id:int}")
async def delete_user(user_id: int) -> None:
    return None


@get("/search")
async def search(q: str) -> dict:
    return {"q": q}


@route("/multi", http_method=["GET", "POST"])
async def multi(request: Request) -> dict:
    return {}


@get("/headers")
async def get_headers(request: Request) -> dict:
    token = request.headers["X-Token"]
    return {"token": token}


@get("/cookies")
async def get_cookies(request: Request) -> dict:
    session = request.cookies.get("session")
    return {"session": session}


@get("/items")
async def list_items() -> list:
    return []


@get("/items/{item_id:int}")
async def get_item(item_id: int) -> dict:
    return {}


router = Router(path="/api", route_handlers=[list_items, get_item])


app = Litestar(route_handlers=[
    index,
    list_users,
    get_user,
    create_user,
    update_user,
    delete_user,
    search,
    multi,
    get_headers,
    get_cookies,
    router,
])
