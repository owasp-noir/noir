from fastapi import APIRouter, FastAPI


def add_routers(app: FastAPI, api_router: APIRouter) -> None:
    # The router arrives as a parameter: which one it is, is not known here.
    app.include_router(api_router)
