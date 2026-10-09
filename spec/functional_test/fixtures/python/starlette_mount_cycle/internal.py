from starlette.applications import Starlette
from starlette.routing import Mount, Route


async def status(request):
    pass


internal = [
    # see [docs
    Route("/status", status),
]
routes = [Mount("/internal", routes=internal)]
app = Starlette(routes=routes)
