from fastapi import APIRouter, Depends, FastAPI, Response

from routes import books


def mark_app(response: Response):
    response.headers["X-Reference"] = "fastapi"


app = FastAPI(dependencies=[Depends(mark_app)], docs_url=None, redoc_url=None, openapi_url=None)
api = APIRouter()
api.include_router(books, prefix="/catalog")
app.include_router(api, prefix="/api")
app.include_router(books, prefix="/archive")


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
