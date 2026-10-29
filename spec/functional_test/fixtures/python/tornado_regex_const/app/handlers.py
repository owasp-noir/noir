import tornado.web

_kid = r"(?P<kernel_id>\w+-\w+)"


class KernelHandler(tornado.web.RequestHandler):
    def get(self, kernel_id):
        pass

    def delete(self, kernel_id):
        pass


class InlineHandler(tornado.web.RequestHandler):
    def get(self, kernel_id):
        pass


class StaticHandler(tornado.web.RequestHandler):
    def get(self, name):
        pass


default_handlers = [
    (r"/api/inline/(?P<kernel_id>\w+-\w+)", InlineHandler),
    (r"/api/pct/%s" % _kid, KernelHandler),
    (rf"/api/fstr/{_kid}", KernelHandler),
    (r"/(robots\.txt|favicon\.ico)", StaticHandler),
]

app = tornado.web.Application(default_handlers)
