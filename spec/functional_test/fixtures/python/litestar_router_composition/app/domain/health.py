from litestar import get


@get("/ping")
async def ping() -> str:
    return "pong"
