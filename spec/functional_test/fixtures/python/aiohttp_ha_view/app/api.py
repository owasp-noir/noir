from aiohttp import web

from app.const import URL_API_CONFIG
from app.http import HomeAssistantView


class APIEntityStateView(HomeAssistantView):
    url = "/api/states/{entity_id}"
    name = "api:entity-state"

    async def get(self, request: web.Request, entity_id: str) -> web.Response:
        return web.Response()

    async def post(self, request: web.Request, entity_id: str) -> web.Response:
        data = await request.json()
        return web.Response(text=data["state"])


class APIStatusView(HomeAssistantView):
    url = "/api/"
    requires_auth = False

    async def get(self, request: web.Request) -> web.Response:
        return web.Response()


class APIConfigView(HomeAssistantView):
    url = URL_API_CONFIG

    async def get(self, request: web.Request) -> web.Response:
        return web.Response()


def setup(hass):
    hass.http.register_view(APIEntityStateView)
    hass.http.register_view(APIStatusView)
