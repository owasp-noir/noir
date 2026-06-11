from fastapi import Depends, FastAPI
from api import api
from db import save_user, audit_log


def auth_required(fn):
    return fn


def rate_limit(_n):
    def deco(fn):
        return fn
    return deco


def build_status():
    return {"ok": True}


def require_admin():
    return True


def export_file(file_path: str):
    audit_log(file_path)
    return {"path": file_path}


app = FastAPI()
app.include_router(api, prefix="/internal")
app.add_api_route("/exports/{file_path:path}", export_file, methods=["GET"])


@app.post("/users")
def create_user(name: str):
    user = save_user(name)
    audit_log(user)
    return {"id": user, "name": name}


@app.get("/healthz")
def healthz():
    return build_status()


# Stacked decorators between the route declaration and the def — used
# to silently skip callee extraction because the analyzer assumed the
# def was at `index + 1`.
@app.get("/profile")
@auth_required
@rate_limit(10)
def profile():
    user = save_user("me")
    audit_log(user)
    return user


# Blank line + comment between the route and the def. Same problem.
@app.delete("/orders/{order_id}")

# permanently removes the row
def remove_order(order_id: int):
    audit_log(order_id)
    return {"deleted": order_id}


# Multi-line typed signature whose `) -> dict:` closer sits at column 0.
# Pre-fix, parse_code_block mistook that line for the block terminator
# and dropped the whole body, so no callees were extracted.
@app.get("/reports")
def list_reports(
    limit: int = 0,
    offset: int = 0,
) -> dict:
    user = save_user("report")
    audit_log(user)
    return {"ok": True}


@app.get(
    "/decorated",
    dependencies=[Depends(require_admin)],
)
def decorated(limit: int = 10):
    audit_log(limit)
    return {"limit": limit}
