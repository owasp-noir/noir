from fastapi import APIRouter

router = APIRouter()
terms_router = APIRouter()
open_router = APIRouter()
twice_router = APIRouter()
limited_router = APIRouter()


@router.get("/{item_id}")
def get_item(item_id: int):
    return {}


@terms_router.get("/{term_id}")
def get_term(term_id: int):
    return {}


@open_router.get("/status")
def status():
    return {}


@twice_router.get("/report")
def report():
    return {}


@limited_router.get("/feed")
def feed():
    return {}
