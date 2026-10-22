from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route


async def filter_items(request):
    tags = request.query_params.getlist('tag')
    return JSONResponse({})


routes = [Route('/filter', filter_items)]
app = Starlette(routes=routes)
