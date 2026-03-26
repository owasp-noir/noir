import tornado.web

class BaseHandler(tornado.web.RequestHandler):
    def get_current_user(self):
        return self.get_secure_cookie("user")

class MainHandler(BaseHandler):
    @tornado.web.authenticated
    def get(self):
        self.write("Hello, " + self.current_user)

class ProfileHandler(BaseHandler):
    @authenticated
    def get(self):
        user = self.current_user
        self.write({"user": user})

class PublicHandler(tornado.web.RequestHandler):
    def get(self):
        self.write({"status": "ok"})
