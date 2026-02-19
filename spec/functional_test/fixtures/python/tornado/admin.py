import tornado.web

class AdminHandler(tornado.web.RequestHandler):
    def get(self):
        token = self.get_cookie("admin_token")
        self.write("Admin panel")

    def delete(self):
        self.set_status(204)
