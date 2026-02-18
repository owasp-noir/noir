import tornado.web

class HealthHandler(tornado.web.RequestHandler):
    def get(self):
        self.write("ok")

    def post(self):
        self.write("created")

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

from handlers import NestedDefHandler, InnerClassHandler

# Test Bug 1: nested def inside handler method doesn't break param extraction
nested_def_routes = [
    (r"/nested-def", NestedDefHandler),
]

app7 = tornado.web.Application(nested_def_routes)

# Test Bug 3: inner class inside handler doesn't break method scanning
inner_class_routes = [
    (r"/inner-class", InnerClassHandler),
]

app8 = tornado.web.Application(inner_class_routes)

# Test Bug 4: route tuple split across lines
multiline_tuple_routes = [
    (r"/multiline-tuple",
     HealthHandler),
]

app9 = tornado.web.Application(multiline_tuple_routes)

# Test Bug 2: multi-line triple-quoted string with ) in Application() call
multiline_triple_routes = [
    (r"/multiline-triple", HealthHandler),
]

app10 = tornado.web.Application(
    cookie_secret="""multi
line)secret""",
    handlers=multiline_triple_routes,
)

# Test: multi-level dotted class name (e.g., subpkg.views.DeepHandler)
import subpkg.views

deep_dotted_routes = [
    (r"/deep", subpkg.views.DeepHandler),
]

app11 = tornado.web.Application(deep_dotted_routes)
