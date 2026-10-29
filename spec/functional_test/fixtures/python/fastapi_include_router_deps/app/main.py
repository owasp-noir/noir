from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request

from app.views import limited_router, open_router, terms_router, twice_router
from app.views import router as items_router


def rate_limit(request: Request):
    return None


def get_current_user(request: Request):
    if not request.headers.get("authorization"):
        raise HTTPException(status_code=401)
    return "u"


api_router = APIRouter()

# control: dependency on the router's own constructor
authed_router = APIRouter(dependencies=[Depends(get_current_user)])


@authed_router.get("/control")
def control():
    return {}


# one hop: dependency on the include_router call
api_router.include_router(items_router, prefix="/items", dependencies=[Depends(get_current_user)])

# two hops: child -> org router -> api_router with the dependency
org_router = APIRouter(prefix="/{organization}")
org_router.include_router(terms_router, prefix="/terms")
api_router.include_router(
    org_router,
    dependencies=[Depends(get_current_user)],
)

api_router.include_router(authed_router)
api_router.include_router(open_router, prefix="/open")

# mounted twice, guarded on one mount only
api_router.include_router(twice_router, prefix="/private", dependencies=[Depends(get_current_user)])
api_router.include_router(twice_router, prefix="/public")

# mounted twice, one mount behind a non-auth dependency
api_router.include_router(limited_router, prefix="/members", dependencies=[Depends(get_current_user)])
api_router.include_router(limited_router, prefix="/limited", dependencies=[Depends(rate_limit)])

app = FastAPI()
app.include_router(api_router)
