import tornado.web


class SearchHandler(tornado.web.RequestHandler):
    def get(self):
        q = self.get_query_argument("q")
        tag = self.get_query_arguments("tag")
        user = self.get_secure_cookie("user")
        self.write("ok")


class TagHandler(tornado.web.RequestHandler):
    def post(self):
        ids = self.get_body_arguments("id")
        self.write("ok")


def make_app():
    return tornado.web.Application([
        (r"/search", SearchHandler),
        (r"/tags", TagHandler),
    ])
