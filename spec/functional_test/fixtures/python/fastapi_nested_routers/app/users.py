from fastapi import APIRouter, Query

router = APIRouter()


# Empty route path under a prefixed router: must resolve to the prefix
# itself (`/api/users`), NOT `/api/users/` with a trailing slash.
@router.get("")
def list_users():
    return []


@router.get("/profile")
def profile(q: str = Query()):
    return {"q": q}
