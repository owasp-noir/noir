from fastapi import APIRouter, Query

router = APIRouter()


@router.get("/profile")
def profile(q: str = Query()):
    return {"q": q}
