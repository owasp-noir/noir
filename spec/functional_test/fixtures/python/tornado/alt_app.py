import tornado.web

class HealthHandler(tornado.web.RequestHandler):
    def get(self):
        self.write("ok")

class StatusHandler(tornado.web.RequestHandler):
    def get(self):
        self.write("running")

handler_routes: list = [
    (r"/health", HealthHandler),
]

multiline_routes =
[
    (r"/status", StatusHandler),
]

app = tornado.web.Application(handlers=handler_routes)
app2 = tornado.web.Application(multiline_routes)
