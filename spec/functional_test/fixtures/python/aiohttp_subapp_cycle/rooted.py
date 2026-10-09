from aiohttp import web


async def deep(request):
    return web.Response(text="ok")


root = web.Application()
first = web.Application()
second = web.Application()
second.router.add_get("/deep", deep)

# `first` and `second` mount each other below a real root; the cycle is
# followed once instead of growing the prefix every lap.
root.add_subapp("/a", first)
first.add_subapp("/b", second)
second.add_subapp("/c", first)
