from aiohttp import web


async def status(request):
    return web.Response(text="ok")


app = web.Application()
sub = web.Application()
sub.router.add_get("/status", status)

# Opposite-direction mounts leave no unmounted root app.
app.add_subapp("/s", sub)
sub.add_subapp("/t", app)
