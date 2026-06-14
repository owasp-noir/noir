import tornado.web
import tornado.websocket
import tornado.escape
from handlers import ApiHandler, SearchHandler
from admin import AdminHandler

class MainHandler(tornado.web.RequestHandler):
    def get(self):
        name = self.get_argument("name", "World")
        self.write(f"Hello, {name}!")

class UserHandler(tornado.web.RequestHandler):
    def get(self, user_id):
        self.write(f"User ID: {user_id}")

    def post(self):
        username = self.get_body_argument("username")
        email = self.get_body_argument("email")
        self.write(f"Created user: {username}")

class AuthHandler(tornado.web.RequestHandler):
    def post(self):
        token = self.get_cookie("auth_token")
        api_key = self.request.headers.get("X-API-Key")
        if token and api_key:
            self.write("Authenticated")

class ChatSocket(tornado.websocket.WebSocketHandler):
    def open(self, room_id):
        token = self.get_argument("token")
        self.write_message(f"joined {room_id} with {token}")

class ProductHandler(tornado.web.RequestHandler):
    def get(self, product_id):
        expand = self.get_argument("expand")
        self.write({"product_id": product_id, "expand": expand})

class NamedItemHandler(tornado.web.RequestHandler):
    def get(self, item_id):
        trace = self.request.headers.get("X-Trace-ID")
        self.write({"item_id": item_id, "trace": trace})

routes = [
    (r"/", MainHandler),
    (r"/users", UserHandler),
    (r"/auth", AuthHandler),
    (r"/ws/([^/]+)", ChatSocket),
    (r"/products/([0-9]+)", ProductHandler),
    (r"/named/(?P<item_id>[^/]+)", NamedItemHandler),
    (r"/api", ApiHandler),
    (r"/search", SearchHandler),
    (r"/items(?:/(\d+))?", SearchHandler),
    (r"/admin", AdminHandler),
]

application = tornado.web.Application(routes)


def routing_examples():
    """Documentation for Tornado routing (these are NOT real routes).

    Tornado's own source documents routing with ``code-block`` examples
    embedded in docstrings, which must not be mistaken for endpoints:

    .. code-block:: python

        app = tornado.web.Application([
            (r"/docstring-phantom", MainHandler),
        ])

        other = tornado.web.Application(handlers=[
            (r"/docstring-phantom-2", MainHandler),
        ])
    """
    return None
