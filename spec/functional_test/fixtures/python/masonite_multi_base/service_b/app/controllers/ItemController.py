from masonite.controllers import Controller
from masonite.request import Request
from masonite.response import Response


class ItemController(Controller):
    def index(self, request: Request, response: Response):
        zone = request.input("zone")
        return response.json({"service": "b", "zone": zone})
