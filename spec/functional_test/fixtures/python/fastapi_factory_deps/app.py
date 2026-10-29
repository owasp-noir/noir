from fastapi import Depends, FastAPI, Header, HTTPException


def require_internal(x_token: str | None = Header(default=None)) -> None:
    if x_token != "expected":
        raise HTTPException(status_code=401, detail="denied")


internal = Depends(require_internal)
limiter = RateLimiter()


def create_app() -> FastAPI:
    app = FastAPI()

    def require_service(x_token: str | None = Header(default=None)) -> None:
        if x_token != "expected":
            raise HTTPException(status_code=401, detail="denied")

    @app.get("/nested")
    def nested(_: None = Depends(require_service)):
        return {}

    @app.get("/aliased", dependencies=[internal])
    def aliased():
        return {}

    @app.get("/direct")
    def direct(_: None = Depends(require_internal)):
        return {}

    @app.get("/literal", dependencies=[Depends(require_internal)])
    def literal():
        return {}

    @app.get("/open")
    def open_route():
        return {}

    @app.get("/limited", dependencies=[limiter])
    def limited():
        return {}

    return app
