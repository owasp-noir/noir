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

ping_routes = [
    (r"/ping", HealthHandler),
]

app3 = tornado.web.Application(
    handlers=ping_routes,
    debug=True,
)

import handlers

dotted_routes = [
    (r"/api/v2", handlers.ApiHandler),
]

app4 = tornado.web.Application(dotted_routes)

# Test: triple-quoted string with ] inside a route list (comment 2821393140)
triple_bracket_routes = [
    (r"/triple-bracket", HealthHandler, {"desc": """This route has
a ] bracket and more text
spanning multiple lines"""}),
]

# Test: multi-line Application() with triple-quoted string containing ) (comment 2821393139)
app5 = tornado.web.Application(
    handlers=triple_bracket_routes,
    cookie_secret="""secret)with)parens""",
    debug=True,
)

# Test: second dotted class name reference (comment 2821393143)
dotted_routes2 = [
    (r"/search/v2", handlers.SearchHandler),
]

app6 = tornado.web.Application(dotted_routes2)
