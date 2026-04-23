from pyramid.config import Configurator
from pyramid.view import view_config
from wsgiref.simple_server import make_server


@view_config(route_name="home", request_method="GET", renderer="json")
def home_view(request):
    q = request.GET["q"]
    lang = request.params.get("lang")
    return {"q": q, "lang": lang}


@view_config(route_name="user", request_method="GET", renderer="json")
def user_view(request):
    uid = request.matchdict["id"]
    token = request.headers.get("X-Token")
    session = request.cookies["session_id"]
    return {"id": uid, "token": token, "session": session}


@view_config(route_name="api_items", request_method="POST", renderer="json")
def create_item(request):
    name = request.POST["name"]
    price = request.POST.get("price")
    return {"name": name, "price": price}


@view_config(route_name="api_login", request_method="POST", renderer="json")
def login_view(request):
    username = request.json_body["username"]
    password = request.json_body.get("password")
    return {"ok": bool(username and password)}


def ping_view(request):
    fmt = request.GET.get("format")
    return {"pong": True, "format": fmt}


def main(global_config, **settings):
    config = Configurator(settings=settings)
    config.add_route("home", "/")
    config.add_route("user", "/users/{id}")
    config.add_route("api_items", "/api/items")
    config.add_route("api_login", "/api/login")
    config.add_route("ping", "/ping")
    config.add_view(ping_view, route_name="ping", request_method="GET", renderer="json")
    config.scan()
    return config.make_wsgi_app()


if __name__ == "__main__":
    app = main({})
    server = make_server("0.0.0.0", 6543, app)
    server.serve_forever()
