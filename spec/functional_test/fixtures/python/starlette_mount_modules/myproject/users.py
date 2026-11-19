from starlette.responses import PlainTextResponse
from starlette.routing import Route


async def users(request):
    return PlainTextResponse("x")


async def user(request):
    return PlainTextResponse(request.path_params["username"])


routes = [
    Route('/', users, methods=['GET', 'POST']),
    Route('/{username}', user),
]
