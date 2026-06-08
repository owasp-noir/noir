from pyramid.config import Configurator
from pyramid.view import view_config


def main(global_config, **settings):
    config = Configurator()
    config.add_route("home", "/a-home")
    config.scan()
    return config.make_wsgi_app()


@view_config(route_name="home", request_method="GET")
def home(request):
    request.params["a"]
    return {}
