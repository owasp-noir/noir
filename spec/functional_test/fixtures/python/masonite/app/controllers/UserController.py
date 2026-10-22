"""A UserController Module."""
from masonite.controllers import Controller
from masonite.request import Request
from masonite.response import Response


class UserController(Controller):
    def store(self, request: Request, response: Response):
        name = request.input("name")
        email = request.input("email")
        return response.json({"name": name, "email": email})

    def show(self, request: Request, response: Response, id):
        return response.json({"id": id})

    def search(self, request: Request, response: Response):
        sort = request.input("sort")
        return response.json({"sort": sort})

    def settings(self, request: Request, response: Response):
        theme = request.input("theme")
        return response.json({"theme": theme})

    def update_profile(self, request: Request, response: Response):
        bio = request.input("bio")
        return response.json({"bio": bio})

    def index(self, request: Request, response: Response):
        page = request.input("page")
        return response.json({"page": page})

    def create(self, request: Request, response: Response):
        username = request.input("username")
        return response.json({"username": username})

    def webhook(self, request: Request, response: Response):
        token = request.header("X-Webhook-Token")
        return response.json({"token": token})

    def touch(self, request: Request, response: Response, id):
        session = request.cookie("session_id")
        return response.json({"id": id, "session": session})
