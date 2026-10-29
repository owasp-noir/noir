from litestar import Litestar

from app.admin import AdminController
from app.controllers import AccessController
from app.search import search

app = Litestar(route_handlers=[AccessController, AdminController, search])
