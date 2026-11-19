from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route


async def invoices(request):
    return PlainTextResponse("x")


async def pay(request):
    return PlainTextResponse("x")


routes = [
    Route('/invoices', invoices),
]

billing_app = Starlette(routes=[Route('/pay', pay, methods=['POST'])])
