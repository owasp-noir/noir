from aiohttp import web


async def items(request):
    tag = request.query.getall('tag')
    kind = request.query.getone('kind')
    trace = request.headers.getall('X-Trace')
    return web.json_response({})


app = web.Application()
app.add_routes([web.get('/items', items)])
