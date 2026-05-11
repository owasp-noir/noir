from pyramid.config import Configurator
from pyramid.view import view_config
from db import fetch_user


@view_config(route_name="user_detail", request_method="GET", renderer="json")
def user_detail(request):
    uid = request.matchdict["uid"]
    user = fetch_user(uid)
    return user


def main(global_config, **settings):
    config = Configurator(settings=settings)
    config.add_route("user_detail", "/users/{uid}")
    config.scan()
    return config.make_wsgi_app()
