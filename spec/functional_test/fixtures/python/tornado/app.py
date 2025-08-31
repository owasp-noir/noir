import tornado.web
import tornado.escape

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

application = tornado.web.Application([
    (r"/", MainHandler),
    (r"/users", UserHandler),
    (r"/auth", AuthHandler),
])