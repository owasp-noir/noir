from starlette.responses import PlainTextResponse
from starlette.routing import Route


async def login(request):
    return PlainTextResponse("x")


routes = [
    Route('/login', login, methods=['POST']),
]
