from fasthtml.common import *

# Mounted with `ar.to_app(app)`; every route sits under the prefix.
ar = APIRouter(prefix="/products")


@ar("/all")
def get():
    return ""


@ar
def details(pid: int):
    return ""


@ar.post("/{pid}/buy")
def buy(pid: int, qty: int):
    return ""


@ar.ws("/live")
async def live(msg: str, send):
    pass
