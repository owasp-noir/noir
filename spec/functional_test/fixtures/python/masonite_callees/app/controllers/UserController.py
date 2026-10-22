from masonite.controllers import Controller
from masonite.response import Response

from app.db import fetch_user


class UserController(Controller):
    def show(self, response: Response, uid):
        user = fetch_user(uid)
        return response.json(user)
