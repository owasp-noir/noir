from litestar import Litestar, get, post
from db import save_user, audit_log


@post("/users")
async def create_user(name: str) -> dict:
    user = save_user(name)
    audit_log(user)
    return {"id": user, "name": name}


@get("/healthz")
async def healthz() -> dict:
    return {"ok": True}


app = Litestar(route_handlers=[create_user, healthz])
