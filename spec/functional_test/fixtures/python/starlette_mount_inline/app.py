from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route


async def items(request):
    return JSONResponse({"q": request.query_params.get("q")})


async def health(request):
    return JSONResponse({})


sub = Starlette(
    routes=[
        Route("/items", items),
    ]
)

app = Starlette(routes=[Route("/health", health), Mount("/v2", app=sub)])
