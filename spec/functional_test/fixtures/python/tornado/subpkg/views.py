import tornado.web

class DeepHandler(tornado.web.RequestHandler):
    def get(self):
        token = self.get_argument("token")
        self.write({"ok": True})
