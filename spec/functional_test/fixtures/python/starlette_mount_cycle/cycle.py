from starlette.applications import Starlette
from starlette.routing import Mount, Route


async def leaf(request):
    pass


async def branch(request):
    pass


# `outer` and `loop` mount each other; the cycle is followed once.
outer = [
    Route("/leaf", leaf),
    Mount("/loop", routes=loop),
]
loop = [
    Route("/branch", branch),
    Mount("/outer", routes=outer),
]
app = Starlette(routes=outer)
