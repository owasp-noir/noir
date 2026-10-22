from typing import cast

from fastopenapi.routers import FlaskRouter

from controllers.fastopenapi import console_router


def init_app(app):
    router = FlaskRouter(app=app, openapi_url="/fastopenapi/openapi.json")

    from controllers import setup

    _ = setup

    # fastopenapi mounts every route of the included router under `prefix`.
    cast(object, router).include_router(console_router, prefix="/console/api")
