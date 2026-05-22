from litestar import get
from litestar.connection import Request


@get("/summary")
async def external_summary(request: Request) -> dict:
    mode = request.query_params.get("mode")
    return {"mode": mode}
