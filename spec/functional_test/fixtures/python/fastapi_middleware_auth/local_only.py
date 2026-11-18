from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI()


@app.middleware("http")
async def local_only(request: Request, call_next):
    if request.client.host != "203.0.113.7":
        return JSONResponse({"detail": "forbidden"}, status_code=403)
    return await call_next(request)


@app.get("/status")
def status():
    return {}
