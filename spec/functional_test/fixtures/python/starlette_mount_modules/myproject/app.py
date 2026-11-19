from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route, Mount

from myproject import users, auth
from myproject.billing import routes as billing_routes, billing_app


async def homepage(request):
    return PlainTextResponse("x")


routes = [
    Route('/', homepage),
    Mount('/w01-users', routes=users.routes),
    Mount('/w02-auth', routes=auth.routes),
    Mount('/w03-billing', routes=billing_routes),
    Mount('/w04-billing-app', app=billing_app),
]

app = Starlette(routes=routes)
