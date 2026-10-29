from litestar import Litestar

from app.controllers import AccessController

app = Litestar(route_handlers=[AccessController])
