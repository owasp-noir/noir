from pyramid.config import Configurator
from pyramid.view import view_config


@view_config(route_name="create", renderer="json")
def create(request):
    name = request.POST["name"]
    return {"name": name}


@view_config(route_name="delete", renderer="json")
def delete(request):
    return {}


@view_config(route_name="patch", request_method="PATCH", renderer="json")
def patch(request):
    return {}


def show(request):
    return {}


def main():
    config = Configurator()
    config.add_route("create", "/things", request_method="POST")
    config.add_route("delete", "/things/{id}", request_method="DELETE")
    config.add_route("patch", "/things/{id}/patch", request_method="POST")
    config.add_route("show", "/show", request_method=("GET", "HEAD"))
    config.add_view(show, route_name="show", renderer="json")
    config.scan()
    return config.make_wsgi_app()
