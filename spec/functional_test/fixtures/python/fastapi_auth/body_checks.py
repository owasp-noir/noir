from fastapi import APIRouter, Depends, Header, HTTPException, Response

router = APIRouter()


@router.get("/bare-if-else")
def bare_if_else(user=Depends(get_optional_user)):
    if user:
        return {"ok": 1}
    else:
        raise HTTPException(status_code=403)


@router.get("/owner-compare/{id}")
def owner_compare(id: int, user=Depends(get_optional_user)):
    if load(id).owner != user:
        raise HTTPException(status_code=403)
    return {}


@router.get("/doc-and-owner/{id}")
def doc_and_owner(id: int, user=Depends(get_optional_user)):
    doc = load(id)
    if doc and doc.owner_id != user.id:
        raise HTTPException(status_code=403)
    return doc


@router.get("/elif-chain/{id}")
def elif_chain(id: int, user=Depends(get_optional_user)):
    if user.role == "admin":
        x = 1
    elif id > 5:
        x = 2
    else:
        raise HTTPException(status_code=403)
    return x


@router.get("/status-attr")
def status_attr(response: Response, user=Depends(get_optional_user)):
    if not user:
        response.status_code = 403
        return {"detail": "no"}
    return {}


@router.get("/paren-in-string")
def paren_in_string(user=Depends(get_optional_user)):
    msg = "(oops"
    if user.role != "admin":
        raise HTTPException(status_code=403)
    return msg


@router.post("/signup")
def signup(settings=Depends(get_settings)):
    if not settings.signup_enabled:
        raise HTTPException(status_code=403)
    return {}


@router.post("/login")
def login(form_data=Depends(get_form)):
    if not check_pw(form_data.username, form_data.password):
        raise HTTPException(status_code=401)
    return {}


@router.get("/loop-else")
def loop_else(user=Depends(get_optional_user)):
    if user:
        pass
    for item in []:
        pass
    else:
        raise HTTPException(status_code=403)
    return {}


async def get_current_user(token: str = Depends(oauth2_scheme)):
    if not token:
        raise HTTPException(status_code=401)
    return token


class ItemView:
    user: dict = Depends(get_current_user)

    @router.get("/view-items/{id}")
    def get_item(self, id: int):
        if load(id).owner != self.user:
            raise HTTPException(status_code=403)
        return {}


def create_token_dependency(expected: str | None):
    async def require_token(
        authorization: str | None = Header(default=None),
    ) -> None:
        if expected is None:
            return
        if authorization != expected:
            raise HTTPException(
                status_code=401,
                detail="invalid token",
            )

    return Depends(require_token)


def create_internal_router(token: str | None) -> APIRouter:
    router = APIRouter(dependencies=[create_token_dependency(token)])

    @router.post("/internal/collect")
    async def collect():
        return {}

    return router
