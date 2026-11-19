from handlers.foo import FooHandler, BarHandler
from plain import PlainView

url_patterns = [
    (r"/p01-foo", FooHandler),
    (r"/p02-bar/(\d+)", BarHandler),
]

# Not a route table: PlainView is a plain class.
other_urls = [
    (r"/plain-view", PlainView),
]
