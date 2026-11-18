from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI()


@app.middleware("http")
async def check_csrf(request: Request, call_next):
    if request.method in ("POST", "PUT", "DELETE"):
        if request.headers.get("x-csrf-token") != request.cookies.get("csrftoken"):
            return JSONResponse({"detail": "bad csrf token"}, status_code=403)
    return await call_next(request)


@app.post("/notes")
def add_note():
    return {}
