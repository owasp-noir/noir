import tornado.web


class FooHandler(tornado.web.RequestHandler):
    def get(self):
        self.write(self.get_argument("q", ""))

    def post(self):
        self.write(self.get_body_argument("name"))


class BarHandler(tornado.web.RequestHandler):
    def get(self, bar_id):
        self.write("x")
