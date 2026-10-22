from masonite.controllers import Controller
from masonite.request import Request
from masonite.response import Response


class ItemController(Controller):
    def index(self, request: Request, response: Response):
        region = request.input("region")
        return response.json({"service": "a", "region": region})
