import tornado.web
class H(tornado.web.RequestHandler):
    def get(self, id):
        pass
app = tornado.web.Application([(r"^/tornado/([0-9]+)\.json$", H)])
