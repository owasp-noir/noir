from fastapi import APIRouter

from .loans import loans

desk = APIRouter(prefix="/desk")
desk.include_router(loans, prefix="/circulation")


@desk.get("/hours")
def hours():
    return {"opens": "09:00"}
