import external_handlers
from litestar import Controller, Litestar, get, post, put, delete, route, Router, websocket, websocket_listener
from litestar.connection import Request
from litestar.handlers import WebsocketListener
from litestar.params import Dependency
from pydantic import BaseModel


class UserCreate(BaseModel):
    name: str
    email: str


class UserUpdate(BaseModel):
    name: str


class ReportCreate(BaseModel):
    title: str


class UserService:
    def get_status(self) -> str:
        return "ok"


def provide_user_service() -> UserService:
    return UserService()


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


@get("/dependency/{user_id:int}")
async def dependency_route(user_id: int, service: UserService = Dependency(provide_user_service), q: str = "") -> dict:
    return {"user_id": user_id, "status": service.get_status(), "q": q}


@route("/multi", http_method=["GET", "POST"])
async def multi(request: Request) -> dict:
    return {}


@websocket("/ws/{room_id:str}")
async def room_socket(socket: WebsocketListener, room_id: str, token: str) -> None:
    await socket.accept()


@websocket_listener("/ws-listener")
async def listener_socket() -> str:
    return "ok"


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


@get("/summary")
async def inline_summary(request: Request) -> dict:
    mode = request.query_params.get("mode")
    return {"mode": mode}


class ReportsController(Controller):
    path = "/reports/{org_id:int}"

    @get("/{report_id:int}")
    async def get_report(self, org_id: int, report_id: int, include_meta: bool = False) -> dict:
        return {"org_id": org_id, "report_id": report_id, "include_meta": include_meta}

    @post("")
    async def create_report(self, org_id: int, data: ReportCreate) -> dict:
        return {"org_id": org_id, "title": data.title}


class AbsoluteController(Controller):
    @get(
        path="/absolute/status",
    )
    async def absolute_status(self) -> dict:
        make_cookie(
            path="/not-a-controller-prefix",
        )
        return {}


router = Router(path="/api", route_handlers=[list_items, get_item])
admin_router = Router(path="/admin", route_handlers=[ReportsController])
external_router = Router(path="/external", route_handlers=[external_handlers.external_summary])


app = Litestar(route_handlers=[
    index,
    list_users,
    get_user,
    create_user,
    update_user,
    delete_user,
    search,
    dependency_route,
    multi,
    room_socket,
    get_headers,
    get_cookies,
    Router(path="/inline", route_handlers=[inline_summary]),
    router,
    admin_router,
    external_router,
    AbsoluteController,
])
