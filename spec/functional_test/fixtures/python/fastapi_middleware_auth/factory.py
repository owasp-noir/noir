import secrets

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

LOCAL_HOSTS = {"app.example.test"}


def build_app(secret: str) -> FastAPI:
    app = FastAPI()

    @app.middleware("http")
    async def gate(request: Request, call_next):
        host = (request.headers.get("host") or "").split(":")[0]
        if host not in LOCAL_HOSTS:
            return JSONResponse({"detail": "local only"}, status_code=403)
        path = request.url.path
        open_path = path.startswith("/assets/") or path == "/signin"
        if not open_path:
            ok = secrets.compare_digest(request.cookies.get("demo_session", ""), secret) or \
                secrets.compare_digest(request.headers.get("x-demo-token", ""), secret)
            if not ok:
                return JSONResponse({"detail": "not signed in"}, status_code=401)
        return await call_next(request)

    @app.get("/assets/{name}")
    def asset(name: str):
        return {}

    @app.get("/signin")
    def signin():
        return {}

    @app.get("/dashboard")
    def dashboard():
        return []

    return app
