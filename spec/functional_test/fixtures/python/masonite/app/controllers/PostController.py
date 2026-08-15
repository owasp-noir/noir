"""A PostController Module — implements every action Route.resource /
Route.api generate so the fixture's resource routes actually resolve."""
from masonite.controllers import Controller
from masonite.request import Request
from masonite.response import Response


class PostController(Controller):
    def index(self, response: Response):
        return response.json([])

    def create(self, response: Response):
        return response.view("posts.create")

    def store(self, request: Request, response: Response):
        title = request.input("title")
        return response.json({"title": title})

    def show(self, response: Response, id):
        return response.json({"id": id})

    def edit(self, response: Response, id):
        return response.json({"id": id})

    def update(self, request: Request, response: Response, id):
        title = request.input("title")
        return response.json({"id": id, "title": title})

    def destroy(self, response: Response, id):
        return response.json({"id": id})
