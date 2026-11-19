from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route, Mount


async def homepage(request):
    return PlainTextResponse("x")


async def users(request):
    return PlainTextResponse("x")


async def user(request):
    return PlainTextResponse("x")


async def posts(request):
    return PlainTextResponse("x")


routes = [
    Route('/', homepage),
    Mount('/x01-users', routes=[
        Route('/', users, methods=['GET', 'POST']),
        Mount('/{username}', routes=[
            Route('/', user),
            Route('/posts', posts),
        ]),
        Route('/x01-after', users),
    ]),
    Route('/x02-tail', homepage),
]

app = Starlette(routes=routes)
