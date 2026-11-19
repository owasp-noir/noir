from fastapi import Depends, FastAPI, Header, HTTPException, Request

app = FastAPI()


def get_current_user(authorization: str | None = Header(default=None)):
    if not authorization:
        raise HTTPException(status_code=401)
    return lookup_user(authorization)


def get_admin_user(current_user=Depends(get_current_user)):
    if not current_user.admin:
        raise HTTPException(status_code=403)
    return current_user


def get_active_user(current_user=Depends(get_current_user)):
    if current_user is None:
        raise HTTPException(status_code=403)
    return current_user


def require_feature(settings=Depends(get_settings)):
    if not settings.signup_enabled:
        raise HTTPException(status_code=403)


def check_token(expected: str | None, authorization: str | None) -> None:
    if authorization != f"Bearer {expected}":
        raise HTTPException(status_code=401, detail="missing bearer token")


def read_session(request: Request):
    return request.session.get("user")


@app.get("/admin/stats")
def admin_stats(user=Depends(get_admin_user)):
    return {}


@app.get("/me")
def me(user=Depends(get_active_user)):
    return user


@app.post("/signup")
def signup(_=Depends(require_feature)):
    return {}


@app.post("/search")
def search(request: Request, authorization: str | None = Header(default=None)):
    """Search, once check_token(...) has passed."""
    check_token(EXPECTED, authorization)
    return {}


@app.post("/maybe")
def maybe(flag: bool, authorization: str | None = Header(default=None)):
    if flag:
        check_token(EXPECTED, authorization)
    return {}


@app.get("/session")
def session(request: Request):
    user = read_session(request)
    return {"user": user}


def create_app() -> FastAPI:
    factory_app = FastAPI()

    def require_internal(authorization: str | None = Header(default=None)) -> None:
        check_token(EXPECTED, authorization)

    internal = Depends(require_internal)

    @factory_app.get("/internal/jobs", dependencies=[internal])
    def jobs():
        return []

    return factory_app


def check_feature_enabled():
    if not settings.FEATURE_REPORTS:
        raise HTTPException(status_code=403, detail="feature disabled")


def get_item_or_403(item_id):
    item = load(item_id)
    if item.hidden:
        raise HTTPException(status_code=403)
    return item


@app.get("/reports")
def reports():
    check_feature_enabled()
    return {}


@app.get("/items/{item_id}")
def read_item(item_id: int):
    item = get_item_or_403(item_id)
    return item


def public_handler():
    return {}


app.add_api_route("/public", public_handler, methods=["GET"])


def private_handler(authorization: str | None = Header(default=None)):
    check_token(EXPECTED, authorization)
    return {}


app.add_api_route("/private", private_handler, methods=["GET"])
