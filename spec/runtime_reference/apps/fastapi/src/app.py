from fastapi import APIRouter, Depends, FastAPI, Response

from routes import books
from routes.circulation import desk
from settings import settings


def mark_app(response: Response):
    response.headers["X-Reference"] = "fastapi"


app = FastAPI(dependencies=[Depends(mark_app)], docs_url=None, redoc_url=None, openapi_url=None)
api = APIRouter()
api.include_router(books, prefix="/catalog")
app.include_router(api, prefix="/api")
app.include_router(books, prefix="/archive")
app.include_router(desk, prefix=settings.member_prefix)

staff = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
staff.include_router(desk, prefix="/v1")


@staff.get("/shift", include_in_schema=False)
def current_shift():
    return "day"


app.mount(settings.staff_mount, staff)


def listing():
    return []


for path in ["/recent", "/popular", "/featured"]:
    app.add_api_route(path, listing, methods=["GET"])

STATUS = "/status"


@app.get(f"{STATUS}/ready")
def ready():
    return True


@app.api_route("/echo", methods=["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "TRACE", "CONNECT"])
def echo():
    return "ok"


draft = APIRouter()
draft.add_api_route("/unpublished", listing)
