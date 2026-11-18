from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI()
keyed = FastAPI()


@app.middleware("http")
async def need_user(request: Request, call_next):
    if request.url.path.startswith("/files/public"):
        return await call_next(request)
    if not request.user.is_authenticated:
        return JSONResponse({"detail": "sign in"}, status_code=401)
    return await call_next(request)


@keyed.middleware("http")
async def need_token(request: Request, call_next):
    if "x-demo-token" not in request.headers:
        return JSONResponse({}, status_code=401)
    return await call_next(request)


@app.get("/profile")
def profile():
    return {}


@app.get("/files/{file_path:path}")
def read_file(file_path: str):
    return {}


@keyed.get("/reports")
def reports():
    return {}
