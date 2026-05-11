import tornado.web

from handlers import ProfileHandler
from helpers import audit_log, save_user


class UsersHandler(tornado.web.RequestHandler):
    def post(self):
        name = self.get_body_argument("name")
        user = save_user(name)
        audit_log(user)
        self.write({"id": user})


routes = [
    (r"/users", UsersHandler),
    (r"/profile", ProfileHandler),
]

app = tornado.web.Application(routes)
