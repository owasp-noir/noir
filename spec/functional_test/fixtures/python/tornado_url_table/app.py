import tornado.ioloop
import tornado.web

from urls import url_patterns


class TornadoApplication(tornado.web.Application):
    def __init__(self):
        tornado.web.Application.__init__(self, url_patterns)


if __name__ == "__main__":
    TornadoApplication().listen(8888)
    tornado.ioloop.IOLoop.current().start()
