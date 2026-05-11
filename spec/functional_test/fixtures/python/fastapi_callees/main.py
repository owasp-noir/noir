from fastapi import FastAPI
from api import api
from db import save_user, audit_log


def auth_required(fn):
    return fn


def rate_limit(_n):
    def deco(fn):
        return fn
    return deco


app = FastAPI()
app.include_router(api, prefix="/internal")


@app.post("/users")
def create_user(name: str):
    user = save_user(name)
    audit_log(user)
    return {"id": user, "name": name}


@app.get("/healthz")
def healthz():
    return {"ok": True}


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
