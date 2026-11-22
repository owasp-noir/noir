from fastapi import FastAPI

from api import router
from versioning import add_routers

app = FastAPI()

add_routers(app, router)


def browse(limit: int = 10):
    return limit


for listing in ["/events", "/news"]:
    app.add_api_route(listing, browse, methods=["POST"])
