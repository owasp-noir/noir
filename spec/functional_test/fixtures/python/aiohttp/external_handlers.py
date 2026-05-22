from aiohttp import web


async def external_patch(request):
    external_id = request.match_info['external_id']
    mode = request.query.get('mode')
    data = await request.json()
    title = data.get('title')
    return web.Response(text=f"external {external_id} {mode} {title}")
