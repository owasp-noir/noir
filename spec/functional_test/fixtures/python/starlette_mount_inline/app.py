from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route
from starlette.staticfiles import StaticFiles


async def items(request):
    return JSONResponse({"q": request.query_params.get("q")})


async def health(request):
    return JSONResponse({})


sub = Starlette(
    routes=[
        Route("/items", items),
    ]
)

pos = Starlette(routes=[Route("/inner", health)])

app = Starlette(routes=[Route("/health", health), Mount("/v2", app=sub), Mount("/static", StaticFiles(directory="s"), name="static")])

app2 = Starlette(
    routes=[
        Mount("/pos", pos),
        Route("/after", health),
    ]
)
