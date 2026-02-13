import tornado.web

class HealthHandler(tornado.web.RequestHandler):
    def get(self):
        self.write("ok")

handler_routes = [
    (r"/health", HealthHandler),
]

app = tornado.web.Application(handlers=handler_routes)
