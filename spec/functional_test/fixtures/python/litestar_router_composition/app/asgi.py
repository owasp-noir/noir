from litestar import Litestar, Router

from app.domain.accounts.controllers import AccessController, UserController
from app.domain.teams.controllers import TeamController
from app.domain.teams.routes import team_router
from app.domain import health

api = Router(path="/u01-api", route_handlers=[AccessController, UserController])
v2 = Router("/u02-v2", route_handlers=[TeamController, team_router, health.ping])

app = Litestar(route_handlers=[api, v2])
