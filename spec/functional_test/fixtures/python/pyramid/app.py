from pyramid.config import Configurator
from pyramid.view import view_config, view_defaults
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


@view_config(route_name="about", request_method="GET", renderer="json")
def about_view(request):
    source = request.params["source"]
    return {"source": source}


@view_config(route_name="external_report", request_method="GET", renderer="json")
def external_report_view(request):
    include = request.params.get("include")
    return {"include": include}


def ping_view(request):
    fmt = request.GET.get("format")
    return {"pong": True, "format": fmt}


@view_defaults(route_name="orders", renderer="json")
class OrdersView:
    def __init__(self, request):
        self.request = request

    @view_config(request_method="GET")
    def list(self):
        status = self.request.params.get("status")
        return {"status": status}

    @view_config(request_method="POST")
    def create(self):
        order_id = self.request.json_body["order_id"]
        return {"order_id": order_id}


# Multi-line @view_defaults: the closing `)` sits directly above the
# class, so the route_name must still be inherited by the methods below.
@view_defaults(
    route_name="reports",
    renderer="json",
    permission="view",
)
class ReportsView:
    def __init__(self, request):
        self.request = request

    @view_config(request_method="GET")
    def list(self):
        scope = self.request.params.get("scope")
        return {"scope": scope}

    @view_config(request_method="DELETE")
    def delete(self):
        return {}


def main(global_config, **settings):
    config = Configurator(settings=settings)
    config.add_route("home", "/")
    config.add_route("user", "/users/{id}")
    config.add_route("api_items", "/api/items")
    config.add_route("api_login", "/api/login")
    config.add_route(pattern="/about", name="about")
    config.add_route("ping", "/ping")
    config.add_route("orders", "/orders")
    config.add_route("reports", "/reports")
    config.add_static_view(
        name="assets",
        path="public",
        cache_max_age=3600,
    )
    config.add_view(ping_view, route_name="ping", request_method="GET", renderer="json")
    config.scan()
    return config.make_wsgi_app()


if __name__ == "__main__":
    app = main({})
    server = make_server("0.0.0.0", 6543, app)
    server.serve_forever()
