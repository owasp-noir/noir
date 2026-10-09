from starlette.applications import Starlette
from starlette.routing import Mount, Route


async def health(request):
    pass


routes = [Route("/health", health)]
# Rebinding the name mounts the old list, not the new one into itself.
routes = [Mount("/v1", routes=routes)]
app = Starlette(routes=routes)
