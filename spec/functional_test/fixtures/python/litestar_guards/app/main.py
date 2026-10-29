from litestar import Controller, Litestar, get
from litestar.connection import ASGIConnection
from litestar.exceptions import PermissionDeniedException
from litestar.handlers.base import BaseRouteHandler


def requires_team_membership(connection: ASGIConnection, _: BaseRouteHandler) -> None:
    if not connection.user.is_member:
        raise PermissionDeniedException("not a member")


class TeamController(Controller):
    @get(path="/api/teams/{team_id:int}", guards=[requires_team_membership])
    async def get_team(self, team_id: int) -> dict:
        return {}


class AdminController(Controller):
    path = "/api/admin"
    guards = [requires_team_membership]

    @get("/stats")
    async def stats(self) -> dict:
        return {}


class OAuthController(Controller):
    @get("/api/auth/oauth/github", name="oauth:github:authorize")
    async def github_authorize(self) -> dict:
        return {}


app = Litestar(route_handlers=[TeamController, AdminController, OAuthController])
