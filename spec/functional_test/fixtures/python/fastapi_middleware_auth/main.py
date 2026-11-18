from fastapi import APIRouter, FastAPI, Request

from .security import login_enabled, sign_in_required, signed_in_user

app = FastAPI()
other = FastAPI()


async def forward(request: Request, call_next):
    return await call_next(request)


@app.middleware("http")
async def add_timing(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Elapsed"] = "0"
    return response


@app.middleware("http")
async def require_sign_in(request: Request, call_next):
    path = request.url.path
    if (
        request.method == "OPTIONS"
        or not login_enabled()
        or not path.startswith("/api")
        or path.startswith("/api/session")
        or path in {"/api/ping", "/api/ping/deep"}
    ):
        return await forward(request, call_next)
    if signed_in_user(request) is not None:
        return await forward(request, call_next)
    response = sign_in_required()
    response.headers.setdefault("X-Trace", "demo")
    return response


@app.get("/api/orders")
def list_orders():
    return []


@app.get("/api/ping")
def ping():
    return {}


@app.post("/api/session/start")
def start_session():
    return {}


@app.get("/home")
def home():
    return {}


@other.get("/api/orders")
def other_orders():
    return []


orders = APIRouter(prefix="/api/orders")
invoices = APIRouter(prefix="/api/invoices")


@orders.get("/{order_id}")
def get_order(order_id: int):
    return {}


@invoices.get("/daily")
def daily_invoices():
    return {}


for router in (
    orders,
    invoices,
):
    app.include_router(router)
other.include_router(invoices)


# An http middleware never runs for a websocket connection.
@app.websocket("/api/orders/live")
async def orders_live(websocket):
    await websocket.accept()
