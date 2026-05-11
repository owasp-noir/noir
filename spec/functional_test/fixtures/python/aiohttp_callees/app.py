from aiohttp import web
from db import save_order

routes = web.RouteTableDef()


@routes.post("/orders")
async def create_order(request):
    data = await request.json()
    order = save_order(data)
    return web.json_response(order)


@routes.get("/healthz")
async def healthz(request):
    return web.json_response({"ok": True})
